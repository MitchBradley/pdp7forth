#!/usr/bin/env python3
"""Compile src/prelude.fs into a kernel image by running it under SimH.

usage: prelude.py LISTING A7OUT PRELUDE OUT [KERNEL_SOURCE]

Boots the assembled kernel at "cold", types the prelude at it, ends with
BYE, then reads all of memory back and writes it (nonzero words only) in
the same "addr: word" form as as7's a7out output. Fails if any prelude
line gets a response other than " ok". The prelude source never takes
space in the image.
"""
import re
import sys

import simh

MAXLINE = 80  # the kernel's TIB


def read_labels(listing):
    labels, in_labels = {}, False
    for line in open(listing):
        if line.startswith("Labels:"):
            in_labels = True
        elif in_labels and line.strip():
            name, addr = line.split()[:2]
            labels[name] = int(addr, 8)
    return labels


def read_image(a7out):
    image = []
    for line in open(a7out):
        addr, word = line.split("\t")[0].split(":")
        word = word.strip()
        image.append((int(addr, 8), int(word, 8)))
    return image


def write_image(image, path):
    with open(path, "w") as f:
        for addr, word in image:
            f.write(f"{addr:06o}: {word:06o}\n")


def prelude_lines(text):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    for n, line in enumerate(lines, 1):
        if len(line) > MAXLINE:
            sys.exit(f"prelude line {n} is longer than {MAXLINE} characters")
        if "\t" in line:
            sys.exit(f"prelude line {n} has a tab; the kernel parses on spaces")
    return lines


DEFINERS = (":", "constant", "variable", "create")


def name_key(name):
    """What a header stores: the length and the first 3 characters."""
    return len(name), name.upper()[:3]


def check_names(kernel_src, text):
    """Exit if a prelude definition collides with an earlier name."""
    seen = {}
    for m in re.finditer(r'^h\.\S+:.*" (\S+)$', kernel_src, re.M):
        seen[name_key(m.group(1))] = m.group(1)
    for n, line in enumerate(prelude_lines(text), 1):
        words = line.split()
        if words and words[0] == "\\":
            continue
        for i, w in enumerate(words[:-1]):
            if w.lower() in DEFINERS:
                name = words[i + 1]
                key = name_key(name)
                if key in seen and seen[key].upper() != name.upper():
                    sys.exit(f"prelude line {n}: {name} collides with "
                             f"{seen[key]} (same length and first 3 "
                             "characters)")
                seen[key] = name


def build(cold, image, text):
    """Return (new image, transcript). Exits if a prelude line fails."""
    lines = prelude_lines(text)
    sim = simh.Sim(image, cold, examine=range(0o20000))
    for line in lines:
        sim.type(line)
    transcript, mem = sim.finish("bye\r")
    responses = transcript.split("\r\n")[1:]  # drop the banner
    for n, line in enumerate(lines):
        # A line's echo is followed by a space, then " ok" on success.
        if n >= len(responses) or not responses[n].endswith(" ok"):
            got = responses[n] if n < len(responses) else "(nothing)"
            sys.exit(f"prelude line {n + 1} failed: {line!r}\n  -> {got!r}")
    new = sorted((a, w) for a, w in mem.items() if a != "ac" and w)
    if len(new) < 100:
        sys.exit("memory dump looks truncated")
    return new, transcript


def main():
    if len(sys.argv) not in (5, 6):
        sys.exit(__doc__)
    listing, a7out, prelude, out = sys.argv[1:5]
    if len(sys.argv) == 6:
        check_names(open(sys.argv[5]).read(), open(prelude).read())
    labels = read_labels(listing)
    image, _ = build(labels["cold"], read_image(a7out), open(prelude).read())
    write_image(image, out)


if __name__ == "__main__":
    main()
