#!/usr/bin/env python3
"""Make a paper tape image for the kernel's TAPE word from a text file.

usage: mktape.py IN OUT

Copies IN and appends ^D (EOT), which ends tape input. Line endings can
be LF or CR LF. In SimH: "attach ptr OUT", then type TAPE in Forth.
"""
import sys

EOT = b"\x04"


def to_tape(text):
    return text.encode("latin-1") + EOT


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[2], "wb") as f:
        f.write(to_tape(open(sys.argv[1]).read()))
