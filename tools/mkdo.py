#!/usr/bin/env python3
"""Write a SimH pdp7 script that loads the kernel and starts it at cold.

usage: mkdo.py [--display] LISTING IMAGE [TAPE]
  IMAGE:     as7 a7out output, or prelude.py's
  TAPE:      a paper tape image (mktape.py) to mount in the reader
  --display: enable the Type 340 display (Open SIMH only)
"""
import sys

args = sys.argv[1:]
display = "--display" in args
args = [a for a in args if a != "--display"]
if len(args) not in (2, 3):
    sys.exit(__doc__)
lst, img = args[:2]
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
if display:
    # G2OUT (the Graphics-2, pdp7-unix's second terminal) shares device 05
    print("set g2out disabled")
    print("set g2in disabled")
    print("set dpy enabled")
if len(args) == 3:
    print(f"attach ptr {args[2]}")
for line in open(img):
    addr, word = line.split("\t")[0].split(":")
    print(f"d {addr} {word.strip()}")
print(f"go {cold}")
