#!/usr/bin/env python3
# Nura DSDS proxy: exposes the second subscription (SIM in slot 1, "secondary") of the single
# Qualcomm modem as a separate QRTR "modem" on the local node, so ModemManager creates a
# second modem object for it.  Each client gets its own upstream QMI client that is bound
# to the secondary subscription before its first request is forwarded.
import socket, struct, select, sys, time, os
AF = 42
NS_PORT = 0xfffffffe
SUB = 1  # secondary
# service -> (bind message id, struct format, value)
BIND = {
    1:  (0xAF, "<I", 1),   # WDS
    2:  (0x54, "<I", 2),   # DMS (1 = primary, 2 = secondary)
    3:  (0x45, "<B", 1),   # NAS
    5:  (0x45, "<B", 1),   # WMS
    9:  (0x44, "<B", 1),   # VOICE
    12: (0x1A, "<B", 1),   # PBM
}
PASS = [10, 11, 26, 36, 42, 47]   # CAT, UIM, WDA, PDC, DSD, DPM: forwarded unchanged
SERVICES = sorted(set(BIND) | set(PASS))
LOG = os.environ.get("DSDS_LOG")
def log(*a):
    if LOG: print(*a, file=sys.stderr, flush=True)

def ns_lookup(service):
    s = socket.socket(AF, socket.SOCK_DGRAM); s.settimeout(2)
    node, _ = s.getsockname()
    s.sendto(struct.pack("<IIIII", 10, service, 0, 0, 0), (node, NS_PORT))
    out = []
    try:
        while True:
            d, a = s.recvfrom(256)
            cmd, sv, inst, nd, pt = struct.unpack("<IIIII", d[:20])
            if cmd != 4: continue
            if sv == 0: break
            out.append((inst, nd, pt))
    except socket.timeout:
        pass
    s.close(); return out

def ns_register(sock, service, instance):
    node, port = sock.getsockname()
    sock.sendto(struct.pack("<IIIII", 4, service, instance, node, port), (node, NS_PORT))

class Proxy:
    def __init__(self, modem_node=0):
        self.modem_node = modem_node
        self.front = {}      # service -> socket
        self.up_addr = {}    # service -> (node,port) of real service
        self.clients = {}    # (service, cnode, cport) -> upstream socket
        self.up2cl = {}      # upstream socket -> (service, cnode, cport)
        self.local = socket.socket(AF, socket.SOCK_DGRAM).getsockname()[0]
        for sv in SERVICES:
            found = [x for x in ns_lookup(sv) if x[1] == modem_node]
            if not found:
                log("service", sv, "not on modem, skipping"); continue
            inst, nd, pt = found[0]
            self.up_addr[sv] = (nd, pt)
            s = socket.socket(AF, socket.SOCK_DGRAM)
            s.bind((self.local, 0))
            ns_register(s, sv, inst)
            self.front[sv] = s
            log("proxying service", sv, "inst", hex(inst), "front port", s.getsockname())
    def upstream(self, sv, cl):
        key = (sv,) + cl
        u = self.clients.get(key)
        if u: return u
        u = socket.socket(AF, socket.SOCK_DGRAM)
        u.bind((self.local, 0))
        if sv in BIND:
            mid, fmt, val = BIND[sv]
            body = struct.pack("<BHH", 1, len(struct.pack(fmt, val)), 0)  # placeholder
            tl = struct.pack("<BH", 1, struct.calcsize(fmt)) + struct.pack(fmt, val)
            u.sendto(struct.pack("<BHHH", 0, 0xB1D0, mid, len(tl)) + tl, self.up_addr[sv])
            u.settimeout(3)
            try:
                d, _ = u.recvfrom(4096)
                log("bind", sv, "->", d.hex())
            except socket.timeout:
                log("bind timeout", sv)
            u.settimeout(None)
        self.clients[key] = u; self.up2cl[u] = key
        return u
    def run(self):
        while True:
            socks = list(self.front.values()) + list(self.up2cl)
            r, _, _ = select.select(socks, [], [])
            for s in r:
                if s in self.up2cl:
                    sv, cn, cp = self.up2cl[s]
                    try: d, a = s.recvfrom(65536)
                    except OSError: continue
                    if a[1] == 0xfffffffe: continue
                    try:
                        self.front[sv].sendto(self.rewrite_up(sv, d), (cn, cp))
                    except OSError:
                        self.drop(s)
                else:
                    sv = [k for k, v in self.front.items() if v is s][0]
                    d, a = s.recvfrom(65536)
                    if a[1] == 0xfffffffe: continue   # control packets
                    u = self.upstream(sv, (a[0], a[1]))
                    d = self.rewrite(sv, d)
                    try:
                        u.sendto(d, self.up_addr[sv])
                    except OSError:
                        log("upstream send failed", sv)
    def drop(self, u):
        key = self.up2cl.pop(u, None)
        if key: self.clients.pop(key, None)
        u.close()
    # ---- UIM view of the secondary subscription -------------------------------------
    # requests: primary-GW session (0) -> secondary-GW session (2) for the file/PIN commands
    UIM_SESSION_MSGS = {0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2A}
    def tlvs(self, body):
        out = []; i = 0
        while i + 3 <= len(body):
            t, l = struct.unpack("<BH", body[i:i+3]); out.append([t, bytearray(body[i+3:i+3+l])]); i += 3 + l
        return out
    def pack(self, hdr, tl):
        body = b"".join(struct.pack("<BH", t, len(v)) + bytes(v) for t, v in tl)
        return hdr[:5] + struct.pack("<H", len(body)) + body
    def rewrite(self, sv, d):
        if sv != 11 or len(d) < 7: return d
        fl, tx, msg, ln = struct.unpack("<BHHH", d[:7])
        if msg not in self.UIM_SESSION_MSGS: return d
        tl = self.tlvs(d[7:7+ln])
        for t, v in tl:
            if t == 0x01 and len(v) >= 1 and v[0] == 0: v[0] = 2
        return self.pack(d, tl)
    def rewrite_up(self, sv, d):
        if sv != 11 or len(d) < 7: return d
        fl, tx, msg, ln = struct.unpack("<BHHH", d[:7])
        if msg in (0x2F, 0x32):          # card status / card status indication
            tl = self.tlvs(d[7:7+ln])
            for t, v in tl:
                if t == 0x10 and len(v) >= 8:
                    pri, p1x, sec, s1x = struct.unpack("<HHHH", bytes(v[:8]))
                    v[:8] = struct.pack("<HHHH", sec, 0xFFFF, pri, 0xFFFF)   # secondary becomes "primary"
            return self.pack(d, tl)
        if msg in (0x47, 0x48):          # slot status (+indication): only slot 1 (secondary SIM) is active
            tl = self.tlvs(d[7:7+ln])
            for t, v in tl:
                if t == 0x10 and len(v) >= 1:
                    n = v[0]; o = 1
                    for i in range(n):
                        if o + 10 > len(v): break
                        ilen = v[o + 9]
                        if i != 0:       # every slot except the first one
                            v[o + 4:o + 8] = struct.pack("<I", 0)    # slot state: inactive
                            v[o + 8] = 0
                        o += 10 + ilen
            return self.pack(d, tl)
        return d

if __name__ == "__main__":
    Proxy().run()
