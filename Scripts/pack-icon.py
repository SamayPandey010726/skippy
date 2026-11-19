import pathlib
import struct
import sys


def pack(iconset, destination):
    entries = [
        (b"icp4", 16, 1), (b"ic11", 16, 2),
        (b"icp5", 32, 1), (b"ic12", 32, 2),
        (b"ic07", 128, 1), (b"ic13", 128, 2),
        (b"ic08", 256, 1), (b"ic14", 256, 2),
        (b"ic09", 512, 1), (b"ic10", 512, 2),
    ]
    chunks = []
    for kind, size, scale in entries:
        suffix = "@2x" if scale == 2 else ""
        source = iconset / f"icon_{size}x{size}{suffix}.png"
        data = source.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 24:
            raise ValueError(f"Invalid PNG: {source}")
        if struct.unpack(">II", data[16:24]) != (size * scale, size * scale):
            raise ValueError(f"Incorrect icon dimensions: {source}")
        chunks.append(kind + struct.pack(">I", len(data) + 8) + data)
    payload = b"".join(chunks)
    destination.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)


if __name__ == "__main__":
    pack(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
