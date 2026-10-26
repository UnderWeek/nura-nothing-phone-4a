#!/usr/bin/env python3
# Joins Qualcomm split firmware (<name>.mdt + <name>.bNN) into a single <name>.mbn for the remoteproc driver.
import struct,sys,os
def squash(d,name,out):
    mdt=open(f'{d}/{name}.mdt','rb').read()
    assert mdt[:4]==b'\x7fELF'
    ei=mdt[4]
    if ei==2:
        phoff,=struct.unpack_from('<Q',mdt,0x20); phentsize,phnum=struct.unpack_from('<HH',mdt,0x36)
    else:
        phoff,=struct.unpack_from('<I',mdt,0x1c); phentsize,phnum=struct.unpack_from('<HH',mdt,0x2a)
    buf=bytearray(mdt)
    n=0
    for i in range(phnum):
        o=phoff+i*phentsize
        if ei==2:
            p_type,p_flags,p_offset,p_vaddr,p_paddr,p_filesz,p_memsz,p_align=struct.unpack_from('<IIQQQQQQ',mdt,o)
        else:
            p_type,p_offset,p_vaddr,p_paddr,p_filesz,p_memsz,p_flags,p_align=struct.unpack_from('<IIIIIIII',mdt,o)
        if not p_filesz: continue
        f=f'{d}/{name}.b{i:02d}'
        if not os.path.exists(f):
            print('  missing',f); continue
        data=open(f,'rb').read()
        if len(buf)<p_offset+len(data): buf.extend(b'\0'*(p_offset+len(data)-len(buf)))
        buf[p_offset:p_offset+len(data)]=data; n+=1
    open(out,'wb').write(buf); print(name,'->',out,len(buf),'bytes,',n,'segments')
# usage: pil-squash.py <dir with modem.img contents (image/)> <output dir>
# e.g.   pil-squash.py ./modem-img/image ./fw/qcom/milos/nothing/frogger
S, O = sys.argv[1], sys.argv[2]
os.makedirs(O, exist_ok=True)
for n in ['adsp','adsp_dtb','cdsp','cdsp_dtb','modem','ipa_fws']:
    squash(S, n, f'{O}/{n}.mbn')
squash(S + '/qca6750', 'wpss', f'{O}/wpss.mbn')
