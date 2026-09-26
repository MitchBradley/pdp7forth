#!/usr/bin/env python3
"""Write a SimH pdp7 script that loads the kernel and starts it at cold.

usage: mkdo.py LISTING IMAGE [TAPE]
  IMAGE: as7 a7out output, or prelude.py's
  TAPE:  a paper tape image (mktape.py) to mount in the reader
"""
import sys

if len(sys.argv) not in (3, 4):
    sys.exit(__doc__)
lst, img = sys.argv[1:3]
cold = None
for line in open(lst):
    f = line.split()
    if len(f) >= 2 and f[0] == "cold":
        cold = f[1]
if cold is None:
    sys.exit("no 'cold' label in " + lst)
print("set cpu 8k")
print("set cpu eae")
print("set tti fdx")  # the kernel echoes; don't let SimH echo too
print("d tti time 30000")  # keyboard at a Model 33's rate; see simh.py
if len(sys.argv) == 4:
    print(f"attach ptr {sys.argv[3]}")
for line in open(img):
    addr, word = line.split("\t")[0].split(":")
    print(f"d {addr} {word.strip()}")
print(f"go {cold}")
