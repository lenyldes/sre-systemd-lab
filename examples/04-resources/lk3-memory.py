#!/usr/bin/env python3
"""Allocate and touch 100 MiB inside the memory-limited service from the README."""

import time

print("Allocating and touching 100 MiB", flush=True)
data = bytearray(100 * 1024 * 1024)
for offset in range(0, len(data), 4096):
    data[offset] = 1
print("Allocation succeeded; keeping the memory for 5 seconds", flush=True)
time.sleep(5)
