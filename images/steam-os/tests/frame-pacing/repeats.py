#!/usr/bin/env python3
"""Count repeated frames in a decoded 480x270 gray stream while the picture moves.

usage: repeats.py frames.gray
A frame counts as repeated when it differs from the previous one by under 15% of
the local median difference. Only stretches with steady motion are counted, so
pan the camera continuously while capturing.
"""
import sys

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view

W, H = 480, 270


def main():
    frames = np.fromfile(sys.argv[1], np.uint8).reshape(-1, H, W).astype(np.int16)
    diff = np.abs(np.diff(frames, axis=0)).mean(axis=(1, 2))
    median = np.median(sliding_window_view(np.pad(diff, 6, mode='edge'), 13), axis=1)
    moving = median > 2.0
    repeated = (diff < 0.15 * median) & moving
    n = int(moving.sum())
    r = int(repeated.sum())
    pct = 100 * r / n if n else 0.0
    print(f'frames {len(frames)}, moving {n}, repeated {r} ({pct:.1f}%, {pct * 0.6:.1f}/s at 60 fps)')
    if n < len(frames) // 2:
        print('warning: little steady motion; pan the camera continuously for a reliable count')


if __name__ == '__main__':
    main()
