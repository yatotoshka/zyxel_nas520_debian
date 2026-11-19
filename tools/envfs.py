#!/usr/bin/env python3
"""Extract / build a barebox envfs image (the contents of the `env` MTD partition).

The NAS520 env lives in the SPI NOR partition `env` (mtd2, 256 KiB). Its format
is barebox `envfs`, and this script understands the variant used by barebox
2011.06.0-svn44305-dirty6 that ships with the NAS520:

    offset  size  field
    0x00    4     magic, always 0x798fba79
    0x04    4     priority (0)
    0x08    4     crc32 of the entries block
    0x0c    4     length of the entries block
    0x10    8     unused (zeros)
    0x18    4     crc32 of bytes 0x00..0x17 (the fields above)
    0x1c    ...   entries, one after another:
                    +0x00  4  constant 0x67a8c78d (vendor build stamp)
                    +0x04  4  file size
                    +0x08  4  name length including the trailing NUL
                    +0x0c  ... name (NUL-terminated, padded to 4 bytes)
                    ...    ... file data (padded to 4 bytes)

Usage:
    envfs.py extract <image> <dir>     # image -> plain directory tree
    envfs.py build   <dir> <image>     # directory tree -> image (256 KiB)
    envfs.py list    <image>           # print entries

`build` needs a template image only to copy the per-entry stamp; pass it with
`--template` (defaults to <dir>/../mtd2_env.bin if present, else 0x67a8c78d).

Worked example (see INSTALL_GUIDE.md, section 9.3):

    ./envfs.py extract nand-dump/mtd2_env.bin env
    $EDITOR env/config env/bin/boot
    ./envfs.py build env env.bin
"""
import os
import struct
import sys
import zlib

MAGIC = 0x798FBA79
HEADER_LEN = 0x1C
DEFAULT_STAMP = 0x67A8C78D
DEFAULT_SIZE = 0x40000  # 256 KiB = one env partition
DIR_MODE = b""


def parse(data):
    magic, prio, body_crc, body_len = struct.unpack("<IIII", data[:16])
    super_crc = struct.unpack("<I", data[0x18:0x1C])[0]
    if magic != MAGIC:
        raise SystemExit(f"bad magic {magic:#010x} (expected {MAGIC:#010x})")
    if zlib.crc32(data[:0x18]) & 0xFFFFFFFF != super_crc:
        print("warning: superblock crc does not match", file=sys.stderr)

    entries = []
    off = HEADER_LEN
    while off + 12 <= len(data):
        stamp, size, namelen = struct.unpack("<III", data[off:off + 12])
        if namelen == 0 or namelen > 128 or size > 1 << 20:
            break
        off += 12
        name = data[off:off + namelen].rstrip(b"\0").decode()
        off += (namelen + 3) & ~3
        body = data[off:off + size]
        off += (size + 3) & ~3
        entries.append((name, stamp, body))
        if off - HEADER_LEN >= body_len:
            break
    return entries, body_crc, body_len


def cmd_list(image):
    entries, crc, length = parse(open(image, "rb").read())
    print(f"entries crc={crc:#010x} len={length}")
    for name, stamp, body in entries:
        print(f"{stamp:#010x} {len(body):8d} {name}")


def cmd_extract(image, outdir):
    entries, _, _ = parse(open(image, "rb").read())
    for name, _stamp, body in entries:
        path = os.path.join(outdir, name.lstrip("/"))
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "wb") as f:
            f.write(body)
        os.chmod(path, 0o755 if name.startswith("/bin/") else 0o644)
    print(f"extracted {len(entries)} files to {outdir}")


def cmd_build(indir, image, template=None):
    stamps = {}
    if template and os.path.exists(template):
        try:
            for name, stamp, _body in parse(open(template, "rb").read())[0]:
                stamps[name] = stamp
        except SystemExit:
            pass

    names = ["/config"]
    bindir = os.path.join(indir, "bin")
    if os.path.isdir(bindir):
        names += ["/bin/" + n for n in sorted(os.listdir(bindir))]

    body = bytearray()
    for name in names:
        path = os.path.join(indir, name.lstrip("/"))
        data = open(path, "rb").read()
        nb = name.encode() + b"\0"
        body += struct.pack("<III", stamps.get(name, DEFAULT_STAMP), len(data), len(nb))
        body += nb + b"\0" * (((len(nb) + 3) & ~3) - len(nb))
        body += data + b"\0" * (((len(data) + 3) & ~3) - len(data))

    crc = zlib.crc32(bytes(body)) & 0xFFFFFFFF
    head = struct.pack("<IIII", MAGIC, 0, crc, len(body)) + b"\0" * 8
    head += struct.pack("<I", zlib.crc32(head) & 0xFFFFFFFF)

    img = head + bytes(body)
    total = max(DEFAULT_SIZE, (len(img) + 0xFFF) & ~0xFFF)
    img += b"\xff" * (total - len(img))
    with open(image, "wb") as f:
        f.write(img)
    print(f"wrote {image}: {len(names)} files, entries crc={crc:#010x}, {total} bytes")


def main():
    args = [a for a in sys.argv[1:]]
    template = None
    if "--template" in args:
        i = args.index("--template")
        template = args[i + 1]
        del args[i:i + 2]
    if len(args) < 2:
        raise SystemExit(__doc__)
    cmd = args[0]
    if cmd == "list":
        cmd_list(args[1])
    elif cmd == "extract":
        cmd_extract(args[1], args[2])
    elif cmd == "build":
        if template is None:
            guess = os.path.join(os.path.dirname(os.path.abspath(args[1])), "mtd2_env.bin")
            template = guess if os.path.exists(guess) else None
        cmd_build(args[1], args[2], template)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
