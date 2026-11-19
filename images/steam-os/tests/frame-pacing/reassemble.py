#!/usr/bin/env python3
"""Rebuild the HEVC/H.264 bitstream from a pcap of Wolf's Moonlight video packets.

usage: reassemble.py capture.pcap out.bitstream
Frames with a missing data shard are skipped (no FEC recovery).
"""
import collections
import struct
import sys

RTP_AND_EXT = 16  # 12-byte RTP header + 4-byte extension
NV_HEADER = 16
FRAME_HEADER = 8


def packets(path):
    with open(path, 'rb') as f:
        magic = struct.unpack('<I', f.read(24)[:4])[0]
        if magic not in (0xa1b2c3d4, 0xa1b23c4d):
            sys.exit('expected a little-endian pcap (tcpdump -w)')
        while True:
            hdr = f.read(16)
            if len(hdr) < 16:
                return
            _, _, incl, _ = struct.unpack('<IIII', hdr)
            data = f.read(incl)
            ihl = (data[14] & 0x0f) * 4
            yield data[14 + ihl + 8:]


def main():
    frames = collections.OrderedDict()
    for p in packets(sys.argv[1]):
        nv = p[RTP_AND_EXT:RTP_AND_EXT + NV_HEADER]
        _, frame_index, _, _, _, _, fec = struct.unpack('<IIBBBBI', nv)
        frame = frames.setdefault(frame_index, {'data_shards': (fec >> 22) & 0x3ff, 'shards': {}})
        frame['shards'][(fec >> 12) & 0x3ff] = p[RTP_AND_EXT + NV_HEADER:]

    incomplete = 0
    with open(sys.argv[2], 'wb') as out:
        for frame in frames.values():
            n = frame['data_shards']
            if any(i not in frame['shards'] for i in range(n)):
                incomplete += 1
                continue
            out.write(b''.join(frame['shards'][i] for i in range(n))[FRAME_HEADER:])
    print(f'frames {len(frames)}, incomplete {incomplete}')


if __name__ == '__main__':
    main()
