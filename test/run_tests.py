#!/usr/bin/env python3
"""Assemble src/kernel.s and run its smoke tests under SimH's pdp7.

Addresses come from the assembler listing, so tests don't rot when code
moves. Each test gets a fresh simulator with the image deposited, runs
from a label until it halts, and checks memory/AC against expectations.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
AS7 = os.path.join(ROOT, "tools/pdp7-unix/tools/as7")
SOP = os.path.join(ROOT, "tools/pdp7-unix/src/sys/sop.s")
SRC = os.path.join(ROOT, "src/kernel.s")


def assemble():
    os.makedirs(BUILD, exist_ok=True)
    lst = os.path.join(BUILD, "kernel.lst")
    img = os.path.join(BUILD, "kernel.a7out")
    for fmt, out in (("list", lst), ("a7out", img)):
        r = subprocess.run(["perl", AS7, "-f", fmt, "-o", out, SOP, SRC],
                           capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit(f"as7 failed:\n{r.stdout}{r.stderr}")
    labels = {}
    in_labels = False
    for line in open(lst):
        if line.startswith("Labels:"):
            in_labels = True
        elif in_labels and line.strip():
            name, addr = line.split()[:2]
            labels[name] = int(addr, 8)
    image = []
    for line in open(img):
        addr, word = line.split("\t")[0].split(":")
        image.append((int(addr, 8), int(word, 8)))
    return labels, image


def sixbit(name):
    s = name.upper()[:3].ljust(3)
    c = [ord(ch) - 0o40 for ch in s]
    return (c[0] << 12) | (c[1] << 6) | c[2]


def count_field(name):
    return len(name) << 13


def run(image, deposits, start, examine):
    """Run from `start`; return {'ac': .., addr: ..} after the halt."""
    cmds = ["set cpu 8k"]
    cmds += [f"d {a:o} {w:o}" for a, w in image]
    cmds += [f"d {a:o} {w:o}" for a, w in deposits]
    cmds.append(f"go {start:o}")
    cmds.append("examine ac")
    cmds += [f"examine {a:o}" for a in examine]
    cmds.append("exit")
    script = os.path.join(BUILD, "run.do")
    with open(script, "w") as f:
        f.write("\n".join(cmds) + "\n")
    r = subprocess.run(["pdp7", script], capture_output=True, text=True,
                       timeout=20)
    if "HALT instruction" not in r.stdout:
        sys.exit(f"did not halt:\n{r.stdout}")
    result = {}
    for m in re.finditer(r"^(\w+):\s+([0-7]+)$", r.stdout, re.M):
        key = m.group(1)
        result["ac" if key == "AC" else int(key, 8)] = int(m.group(2), 8)
    return result


def main():
    labels, image = assemble()
    L = labels
    failures = 0

    def check(desc, got, want):
        nonlocal failures
        ok = got == want
        failures += not ok
        print(f"{'PASS' if ok else 'FAIL'}: {desc}: got {got:06o}"
              + ("" if ok else f", want {want:06o}"))

    # Test 1: CAL cell -> nest -> GO -> BYE (push) -> EXIT -> halt1.
    SP, RP = 0o12, 0o11
    r = run(image, [], L["start"], [SP, RP, L["dstack"]])
    check("call/return: SP after one push", r[SP], L["dstack"])
    check("call/return: pushed value", r[L["dstack"]], 0o123456)
    check("call/return: RP back to empty", r[RP], L["rstack"] - 1)

    # Test 2: find, covering chain head, a two-link walk, and a miss.
    for name, want in (("GO", L["go.body"]), ("EXIT", L["ex.body"]),
                       ("BYE", L["bye.body"]), ("DUP", 0o777777),
                       ("BY", 0o777777)):
        deps = [(L["tcnt"], count_field(name)), (L["tname"], sixbit(name))]
        r = run(image, deps, L["ftest"], [])
        check(f"find {name}", r["ac"], want)

    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
