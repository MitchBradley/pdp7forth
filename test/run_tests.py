#!/usr/bin/env python3
"""Assemble the kernel with test/tests.s and run the tests under SimH.

Addresses come from the assembler listing, so tests don't rot when code
moves. Each test gets a fresh simulator with the image deposited, runs
from a label until it halts, and checks memory, AC, and console output.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
AS7 = os.path.join(ROOT, "tools/pdp7-unix/tools/as7")
SRCS = [os.path.join(ROOT, f) for f in (
    "tools/pdp7-unix/src/sys/sop.s", "src/kernel.s", "test/tests.s",
    "src/end.s")]
SP, RP = 0o12, 0o11
MASK = 0o777777


def assemble():
    os.makedirs(BUILD, exist_ok=True)
    lst = os.path.join(BUILD, "test.lst")
    img = os.path.join(BUILD, "test.a7out")
    for fmt, out in (("list", lst), ("a7out", img)):
        r = subprocess.run(["perl", AS7, "-f", fmt, "-o", out] + SRCS,
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
    return (len(name) << 13) & MASK


class Result(dict):
    output = ""


def run(image, deposits, start, examine, stdin=""):
    """Run from `start` until it halts; return AC, examined words, output."""
    cmds = ["set cpu 8k", "set cpu eae", "set tti fdx", "set tti 8b"]
    cmds += [f"d {a:o} {w & MASK:o}" for a, w in image]
    cmds += [f"d {a:o} {w & MASK:o}" for a, w in deposits]
    cmds.append(f"go {start:o}")
    cmds.append("examine ac")
    cmds += [f"examine {a:o}" for a in examine]
    cmds.append("exit")
    script = os.path.join(BUILD, "run.do")
    with open(script, "w") as f:
        f.write("\n".join(cmds) + "\n")
    try:
        r = subprocess.run(["pdp7", script], input=stdin.encode("latin-1"),
                           capture_output=True, timeout=20)
    except subprocess.TimeoutExpired:
        sys.exit(f"timed out running from {start:o} (hung or waiting for "
                 "input)")
    r.stdout = r.stdout.decode("latin-1")
    if "HALT instruction" not in r.stdout:
        sys.exit(f"did not halt:\n{r.stdout}")
    result = Result()
    for m in re.finditer(r"^(\w+):\s+([0-7]+)$", r.stdout, re.M):
        key = m.group(1)
        result["ac" if key == "AC" else int(key, 8)] = int(m.group(2), 8)
    out = r.stdout
    for pat in (r"PDP-7 simulator V[\d.\-]+\n", r"\nHALT instruction.*\n",
                r"^\w+:\s+[0-7]+\n", r"Goodbye\n"):
        out = re.sub(pat, "", out, flags=re.M)
    result.output = out[:-1] if out.endswith("\n") else out
    return result


def main():
    L, image = assemble()
    failures = 0

    def check(desc, got, want):
        nonlocal failures
        ok = got == want
        failures += not ok
        fmt = (lambda v: f"{v:06o}") if isinstance(want, int) else repr
        print(f"{'PASS' if ok else 'FAIL'}: {desc}: got {fmt(got)}"
              + ("" if ok else f", want {fmt(want)}"))

    def stack_after(dep_stack, deposits, start, n_out, stdin=""):
        """Run with dep_stack preloaded; return (stack contents, result)."""
        deps = [(L["dstack"] + k, v) for k, v in enumerate(dep_stack)]
        deps.append((SP, L["dstack"] + len(dep_stack) - 1))
        slots = [L["dstack"] + k for k in range(max(n_out, 1))]
        r = run(image, deps + deposits, start, [SP, RP] + slots, stdin)
        depth = r[SP] - L["dstack"] + 1
        return [r[s] for s in slots[:depth]], r

    def prim(name, cell, stack, want, stdin=""):
        deposits = [(L["tip"], L["tcell"] - 1), (L["tcell"], cell)]
        got, r = stack_after(stack, deposits, L["trun"], len(want), stdin)
        check(f"{name} {stack}", got, [w & MASK for w in want])
        check(f"{name}: RP empty", r[RP], L["rstack"] - 1)
        return r

    jmp = lambda label: 0o600000 | L[label]

    # --- call/return: CAL cell -> nest -> GO -> BYE (push) -> EXIT ---
    r = run(image, [], L["start"], [SP, RP, L["dstack"]])
    check("call/return: SP after one push", r[SP], L["dstack"])
    check("call/return: pushed value", r[L["dstack"]], 0o123456)
    check("call/return: RP back to empty", r[RP], L["rstack"] - 1)

    # --- find: head of the chain down to the oldest entry, plus misses ---
    for name, want in (("BASE", L["base"]), ("U<", L["ult"]),
                       ("0=", L["zeq"]), ("DUP", L["dup"]),
                       ("?BRANCH", L["qbran"]), ("BRANCH", L["bran"]),
                       ("EXIT", L["ex.body"]), ("ROT", MASK),
                       ("BAS", MASK)):
        deps = [(L["tcnt"], count_field(name)), (L["tname"], sixbit(name))]
        r = run(image, deps, L["ftest"], [])
        check(f"find {name}", r["ac"], want)

    # --- flow control through hand-built threads ---
    for thread, want in (("tqf", [0o222]), ("tqt", [0o111, 0o222]),
                         ("tbr", [0o222]), ("tlp0", [0, 1, 2, 3, 4]),
                         ("tlp3", [3, 4, 5, 6])):
        got, r = stack_after([], [(L["tip"], L[thread] - 1)], L["trun"],
                             len(want))
        check(f"{thread}: stack", got, want)
        check(f"{thread}: RP back to empty", r[RP], L["rstack"] - 1)

    # --- primitives ---
    B = 0o400000  # sign bit
    for name, label, stack, want in (
            ("DUP", "dup", [5], [5, 5]),
            ("DROP", "drop", [5, 6], [5]),
            ("SWAP", "swap", [1, 2], [2, 1]),
            ("OVER", "over", [1, 2], [1, 2, 1]),
            ("@", "fetch", [L["byemark"]], [0o123456]),
            ("@ via LAW-form address", "fetch",
             [0o760000 | L["byemark"]], [0o123456]),
            ("+", "plus", [3, 4], [7]),
            ("+ wraps", "plus", [-1, 1], [0]),
            ("-", "minus", [3, 5], [-2]),
            ("AND", "and.b", [0o707070, 0o770077], [0o700070]),
            ("OR", "or.b", [0o707070, 0o770077], [0o777077]),
            ("XOR", "xor.b", [0o707070, 0o770077], [0o077007]),
            ("INVERT", "invert", [0], [-1]),
            ("NEGATE", "negate", [5], [-5]),
            ("NEGATE 0", "negate", [0], [0]),
            ("= equal", "equal", [9, 9], [-1]),
            ("= differ", "equal", [9, 8], [0]),
            ("U< 1 2", "ult", [1, 2], [-1]),
            ("U< 2 1", "ult", [2, 1], [0]),
            ("U< 2 2", "ult", [2, 2], [0]),
            ("U< 1 -1", "ult", [1, -1], [-1]),
            ("< -1 1", "less", [-1, 1], [-1]),
            ("< 1 -1", "less", [1, -1], [0]),
            ("< 2 2", "less", [2, 2], [0]),
            ("< min max", "less", [B, B - 1], [-1]),
            ("< max min", "less", [B - 1, B], [0]),
            ("0= 0", "zeq", [0], [-1]),
            ("0= 7", "zeq", [7], [0]),
            ("0< -3", "zlt", [-3], [-1]),
            ("0< 0", "zlt", [0], [0]),
            ("*", "star", [6, 7], [42]),
            ("* signed", "star", [-6, 7], [-42]),
            ("* both negative", "star", [-6, -7], [42]),
            ("/", "slash", [43, 7], [6]),
            ("/ negative dividend", "slash", [-43, 7], [-6]),
            ("/ negative divisor", "slash", [43, -7], [-6]),
            ("MOD", "mod", [43, 7], [1]),
            ("/ both negative", "slash", [-43, -7], [6]),
            ("/ exact", "slash", [42, 7], [6]),
            ("MOD negative dividend", "mod", [-43, 7], [-1]),
            ("MOD negative divisor", "mod", [43, -7], [1]),
            ("MOD both negative", "mod", [-43, -7], [-1]),
            ("* large", "star", [1000, 100], [100000])):
        prim(name, jmp(label), stack, want)

    # >R R@ R> round trip, checked through the stacks.
    got, r = stack_after([4], [(L["tip"], L["tcell"] - 1),
                               (L["tcell"], jmp("tor"))], L["trun"], 1)
    check(">R: RP after", r[RP], L["rstack"])
    deps = [(L["rstack"], 0o4321), (RP, L["rstack"]),
            (L["tip"], L["tcell"] - 1), (L["tcell"], jmp("rat"))]
    got, r = stack_after([], deps, L["trun"], 1)
    check("R@", got, [0o4321])
    check("R@: RP unchanged", r[RP], L["rstack"])
    deps[3] = (L["tcell"], jmp("rfrom"))
    got, r = stack_after([], deps, L["trun"], 1)
    check("R>", got, [0o4321])
    check("R>: RP empty", r[RP], L["rstack"] - 1)

    # ! stores, and BASE's cell pushes its LAW-form address.
    scratch = L["res"]
    prim("!", jmp("store"), [0o555, scratch], [])
    r = run(image, [(L["dstack"], 0o555), (L["dstack"] + 1, scratch),
                    (SP, L["dstack"] + 1), (L["tip"], L["tcell"] - 1),
                    (L["tcell"], jmp("store"))], L["trun"], [scratch])
    check("!: stored", r[scratch], 0o555)
    prim("BASE cell", 0o760000 | L["base"], [], [0o760000 | L["base"]])

    # --- console ---
    r = prim("EMIT", jmp("emit"), [ord("A")], [])
    check("EMIT output", r.output, "A")
    prim("KEY", jmp("key"), [], [ord("Z")], stdin="Z")
    prim("KEY strips bit 8", jmp("key"), [], [ord("Q")],
         stdin=chr(ord("Q") | 0o200))

    # --- accept + parse ---
    def parsed(line):
        r = run(image, [], L["tpar"], range(L["res"], L["res"] + 0o40),
                stdin=line + "\r")
        toks, k = [], L["res"]
        while r[k]:
            toks.append((r[k], r[k + 1], r[k + 2]))
            k += 3
        return toks, r

    for line, words in (("DUP", ["DUP"]),
                        ("  swap   OVER x ", ["SWAP", "OVER", "X"]),
                        ("abcdef ?BRANCH", ["ABCDEF", "?BRANCH"]),
                        ("", [])):
        toks, r = parsed(line)
        want = [(len(w), count_field(w), sixbit(w)) for w in words]
        check(f"parse {line!r}", toks, want)
        check(f"echo {line!r}", r.output, line)
    toks, r = parsed("AB\x7fC D\x08E")
    check("parse with rubout/backspace",
          toks, [(2, count_field("AC"), sixbit("AC")),
                 (1, count_field("E"), sixbit("E"))])
    toks, r = parsed("\x7f\x08X")
    check("rubout on an empty line", toks,
          [(1, count_field("X"), sixbit("X"))])
    long_line = "X" * 90
    toks, r = parsed(long_line)
    check("accept stops at 80 chars", [t[0] for t in toks], [80])

    # --- number ---
    def numbers(line, base=10):
        r = run(image, [(L["base"], base)], L["tnum"],
                range(L["res"], L["res"] + 0o40), stdin=line + "\r")
        return [(r[L["res"] + 2 * k], r[L["res"] + 2 * k + 1])
                for k in range(len(line.split()))]

    ok = lambda v: (1, v & MASK)
    bad = (0, 0)
    check("number decimal", numbers("0 7 42 131071"),
          [ok(0), ok(7), ok(42), ok(131071)])
    check("number negative", numbers("-5 -0 -"), [ok(-5), ok(0), bad])
    check("number rejects", numbers("12x 9: A @"), [bad, bad, bad, bad])
    check("number octal", numbers("17 8 -10", base=8), [ok(15), bad, ok(-8)])
    check("number hex", numbers("ff FF 1a G", base=16),
          [ok(255), ok(255), ok(26), bad])

    print(f"\n{'FAILED' if failures else 'OK'}: {failures} failure(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
