#!/usr/bin/env python3
"""Send the rootfs tarball to the phone's stage2 receiver (it unpacks into RAM and switch_root's).

usage: send-rootfs.py rootfs.tar.gz [iface]
The phone shows up as a USB ethernet device; stage2 listens on [::]:4444 at fe80::ff:fe00:1.
"""
import socket, sys, time
path = sys.argv[1]
iface = sys.argv[2] if len(sys.argv) > 2 else "en5"
addr = ("fe80::ff:fe00:1%" + iface, 4444)
for attempt in range(120):
    try:
        info = socket.getaddrinfo(addr[0], addr[1], socket.AF_INET6, socket.SOCK_STREAM)[0][4]
        s = socket.create_connection(info, timeout=5)
        break
    except OSError:
        time.sleep(2)
else:
    sys.exit("phone not reachable: is stage2 up and the USB ethernet interface present?")
s.settimeout(None)
sent = 0
with open(path, "rb") as f:
    while chunk := f.read(1 << 20):
        s.sendall(chunk); sent += len(chunk)
s.shutdown(socket.SHUT_WR)
s.close()
print("sent %d MB" % (sent >> 20))
