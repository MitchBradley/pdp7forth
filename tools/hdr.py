#!/usr/bin/env python3
"""Print as7 header lines for a kernel dictionary entry.

usage: hdr.py LABEL PREV TAG NAME [imm]
  LABEL  header label to define (e.g. h.dup)
  PREV   previous header label, or 0 for the first entry
  TAG    colon | prim | const | var
  NAME   Forth name (count + first 3 chars, SIXBIT, upper-cased)
  imm    mark the word immediate
"""
import sys


def header(label, prev, tag, name, imm=False):
    if not 1 <= len(name) <= 31:
        sys.exit(f"{name}: name length must be 1..31")
    s = name.upper()[:3].ljust(3)
    c = [ord(ch) - 0o40 for ch in s]
    if any(not 0 <= x <= 0o77 for x in c):
        sys.exit(f"{name}: character outside SIXBIT range")
    word1 = (c[0] << 12) | (c[1] << 6) | c[2]
    count = (len(name) << 13) | (0o10000 if imm else 0)
    # "+", not as7's default "|": header addresses overlap the tag bits.
    link = "" if prev == "0" else f"+{label}-{prev}-1"
    return (f"{label}:\t0{count:06o}+tag.{tag}{link}\t\" {name}\n"
            f"\t0{word1:06o}")


if __name__ == "__main__":
    if len(sys.argv) not in (5, 6) or sys.argv[5:] not in ([], ["imm"]):
        sys.exit(__doc__)
    print(header(*sys.argv[1:5], imm=len(sys.argv) == 6))
