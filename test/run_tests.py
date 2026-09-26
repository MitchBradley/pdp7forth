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
sys.path.insert(0, os.path.join(ROOT, "tools"))
import prelude  # noqa: E402
import simh  # noqa: E402
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
    """Run from `start` until it halts; return AC, examined words, output.
    stdin arrives unpaced, so keep it to one line."""
    sim = simh.Sim(image, start, deposits, examine)
    try:
        output, values = sim.finish(stdin, timeout=20)
    except subprocess.TimeoutExpired:
        sys.exit(f"timed out running from {start:o} (hung or waiting for "
                 "input)")
    result = Result(values)
    result.output = output
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
    for name, want in (("BYE", L["h.bye"]), ("BASE", L["h.base"]),
                       ("U<", L["h.ult"]), ("0=", L["h.zeq"]),
                       ("DUP", L["h.dup"]), ("?BRANCH", L["h.qbran"]),
                       ("BRANCH", L["h.bran"]), ("EXIT", L["h.ex"]),
                       ("ROT", MASK), ("BAS", MASK)):
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

    # EXECUTE on each tag, through mkcell.
    prim("EXECUTE primitive", jmp("execute"), [3, L["h.dup"]], [3, 3])
    prim("EXECUTE variable", jmp("execute"), [L["h.base"]],
         [0o760000 | L["base"]])

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
        check(f"echo {line!r}", r.output, line + " ")
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

    # --- interactive sessions, on an image with the prelude compiled in ---
    ptext = open(os.path.join(ROOT, "src/prelude.fs")).read()
    prelude.check_names(open(os.path.join(ROOT, "src/kernel.s")).read(),
                        ptext)
    pimage, _ = prelude.build(L["cold"], image, ptext)
    pword = dict(pimage)

    def session(desc, exchanges, examine=(), tape=None):
        """exchanges: (line, response) pairs; response follows the echo,
        and for TAPE includes everything read from the tape. Each line is
        typed once the transcript so far has appeared."""
        want = "PDP-7 FORTH\r\n"
        sim = simh.Sim(pimage, L["cold"], examine=[SP, RP] + list(examine),
                       tape=tape)
        try:
            for line, resp in exchanges:
                sim.send(line + "\r")
                want += f"{line} {resp}"
                sim.wait_for(re.escape(want.encode("latin-1")), timeout=5)
        except RuntimeError:
            pass  # the transcript check below reports the difference
        want += "bye "
        try:
            output, values = sim.finish("bye\r", timeout=10)
        except RuntimeError as e:
            check(f"session {desc}", str(e), want)
            return Result()
        r = Result(values)
        r.output = output
        check(f"session {desc}", r.output, want)
        return r

    ok = " ok\r\n"
    r = session("arithmetic and output", [
        ("2 3 + .", "5 " + ok),
        ("7 2 - . 7 -2 * . 7 2 / . 7 2 mod .", "5 -14 3 1 " + ok),
        ("-131072 . 131071 .", "-131072 131071 " + ok),
        ("2 DUP + .", "4 " + ok),
        ("16 base ! ff . -1 . a base !", "FF -1 " + ok),
        ("8 base ! 777 . 12 base !", "777 " + ok),
        ("1 ( 2 ) 3 + . \\ 99 .", "4 " + ok),
        ("65 emit 66 emit cr", "AB\r\n" + ok),
    ])
    check("session arithmetic: stack empty", r[SP], L["dstack"] - 1)
    check("session arithmetic: RP holds only BYE's EXECUTE frame", r[RP],
          L["rstack"])

    session("colon definitions", [
        (": sq dup * ;", ok),
        ("7 sq .", "49 " + ok),
        (": a1 1 ; : a2 a1 a1 + ; : a3 a2 a2 * ;", ok),
        ("a3 .", "4 " + ok),
        (": neg -7 . ; neg", "-7 " + ok),
    ])

    session("control flow", [
        (": t 3 0 do i . loop ; t", "0 1 2 " + ok),
        (": f 0= if 11 else 22 then . ; 0 f 1 f", "11 22 " + ok),
        (": g if 33 . then ; 0 g 1 g", "33 " + ok),
        (": c 3 begin dup . 1 - dup 0= until drop ; c", "3 2 1 " + ok),
        (": w 3 begin dup while dup . 1 - repeat drop ; w", "3 2 1 " + ok),
        (": h begin dup . 1 - dup 0< if drop exit then again ; 2 h",
         "2 1 0 " + ok),
        (": n 2 0 do 2 0 do j 10 * i + . loop loop ; n", "0 1 10 11 " + ok),
        (": n3 2 0 do 2 0 do 2 0 do j . loop loop loop ; n3",
         "0 0 1 1 0 0 1 1 " + ok),
    ])

    r = session("data", [
        ("variable v 5 v ! v @ .", "5 " + ok),
        ("10 constant ten ten .", "10 " + ok),
        ("create arr 1 , 2 , arr @ arr 1 + @ + .", "3 " + ok),
        ("here 3 allot here swap - .", "3 " + ok),
        ("state @ .", "0 " + ok),
    ])

    session("xts", [
        ("5 ' dup execute . .", "5 5 " + ok),
        (": five 5 ; ' five execute .", "5 " + ok),
        ("' base execute @ .", "10 " + ok),
        ("7 constant sev ' sev execute .", "7 " + ok),
        (": c1 [ ' dup compile, ] ; 4 c1 . .", "4 4 " + ok),
        (": i5 5 ; immediate : u i5 literal ; u .", "5 " + ok),
        ("' nosuch", "nosuch ?\r\n"),
    ])

    r = session("errors", [
        ("foo", "foo ?\r\n"),
        ("1 2 foo 3 .", "foo ?\r\n"),
        ("drop", " stack?\r\n"),
        (";", "; ?\r\n"),
        (":", " name?\r\n"),
        ("variable hh here hh !", ok),
        (": bad xyz", "xyz ?\r\n"),
        ("here hh @ = .", "-1 " + ok),
        ("bad", "bad ?\r\n"),
        (": q 1 2 quit 3 ; q", ""),
        (". .", "2 1 " + ok),
    ])
    check("session errors: stack empty", r[SP], L["dstack"] - 1)

    session("link span", [
        ("create big 600 allot : x ;", "x far?\r\n"),
    ])
    session("dictionary full", [
        ("create z 7000 allot", "allot full?\r\n"),
    ])
    r = session("literal pool", [
        (": p1 12345 ; : p2 12345 ; : p3 -12345 ; : p4 10 ;", ok),
        ("p1 p2 + . p3 . p4 .", "24690 -12345 10 " + ok),
    ], examine=[L["pool"]])
    check("literal pool: equal values share an entry (10 is already "
          "pooled by the prelude)", r[L["pool"]], pword[L["pool"]] - 2)

    session("strings", [
        (': s1 ." ab" ; : s2 ." abc" ; : s3 ." " ; s1 s2 s3', "ababc" + ok),
        (': s4 ." x" 7 . ." y" ; s4', "x7 y" + ok),
        (': s5 ." unterminated', ok),
        ("; s5", "unterminated" + ok),
    ])

    session("prelude words", [
        ("5 3 max . 3 5 max . 5 3 min . -4 abs . 4 abs .", "5 5 3 4 4 " + ok),
        ("1 2 3 rot . . . 1 2 3 -rot . . .", "1 3 2 2 1 3 " + ok),
        ("1 2 nip . 1 2 tuck . . . 1 2 2dup . . . . 1 2 2drop",
         "2 2 1 2 2 1 2 1 " + ok),
        ("0 ?dup . 5 ?dup . .", "0 5 5 " + ok),
        ("2 1 > . 1 2 > . 1 2 <> . 2 2 <> . 3 0> . -3 0> . 5 0<> .",
         "-1 0 -1 0 -1 0 -1 " + ok),
        ("variable w 5 w ! 3 w +! w @ .", "8 " + ok),
        ("true . false . bl . 7 1+ . 7 1- . 4 cell+ .", "-1 0 32 8 6 5 " + ok),
        ("hex ff . octal 777 . decimal 99 .", "FF 777 99 " + ok),
        ("65 emit space 66 emit 3 spaces 67 emit 0 spaces", "A B   C" + ok),
        (": d2 ['] dup execute ; 6 d2 . .", "6 6 " + ok),
    ])

    # --- paper tape input ---
    tape = (b"\0\0\0"                      # blank leader
            b"1 2 + .\n"
            b": sq dup * ;\r\n"             # CR LF line endings work too
            b"5 sq .\n\x04"
            b"sq sq .\x04"                   # ^D mid-line ends the line
            b"foo\n2 .\n\x04")              # an error stops tape input
    session("paper tape", [
        ("tape", ok + "1 2 + . 3 " + ok + ": sq dup * ; " + ok
         + "5 sq . 25 " + ok),
        ("7 sq .", "49 " + ok),              # back at the keyboard after ^D
        ("3 tape", ok + "sq sq . 81 " + ok),  # resumes; tape sees the 3
        ("tape", ok + "foo foo ?\r\n"),
        ("4 .", "4 " + ok),                  # the error returned control here
        ("tape", ok + "2 . 2 " + ok),
    ], tape=tape)

    # EOT, the visible alternative to ^D: ends tape input, and the rest of
    # its line is ignored (typed at the keyboard, it's just a comment).
    session("EOT", [
        ("tape", ok + "1 . 1 " + ok + "eot 2 . " + ok),
        ("5 . eot 6 .", "5 " + ok),
        ("tape", ok + "3 . 3 " + ok),
    ], tape=b"1 .\neot 2 .\n3 .\n\x04")

    # ^D at the keyboard halts, like BYE.
    sim = simh.Sim(pimage, L["cold"])
    sim.type("1 .")
    output, _ = sim.finish("\x04", timeout=10)
    check("^D from the keyboard halts", output,
          "PDP-7 FORTH\r\n1 . 1 " + ok)

    session("redefinition warnings", [
        (": sq ;", ok),
        (": sq ;", "sq redefined" + ok),
        (": cellx ;", "cellx redefined" + ok),  # same length/prefix as CELL+
        ("5 constant sq sq .", "sq redefined5 " + ok),
        ("variable ab variable abc variable ab", "ab redefined" + ok),
    ])

    # WORDS: rebuild the expected listing from the image's own headers.
    def expected_words():
        text, col, p = "\r\n", 0, pword[L["latest"]]
        while True:
            w0, w1 = pword.get(p, 0), pword.get(p + 1, 0)
            count = w0 >> 13
            stored = "".join(chr(((w1 >> sh) & 0o77) + 0o40)
                             for sh in (12, 6, 0))
            text += (stored[:count] + "_" * max(0, count - 3)) + " "
            col += count + 1
            if col >= 60:
                text, col = text + "\r\n", 0
            if not w0 & 0o777:
                return text
            p -= (w0 & 0o777) + 1

    want_words = expected_words()
    r = session("WORDS", [("words", want_words + ok)])
    listing = r.output.split("\r\n")
    check("WORDS: no line over 72 columns",
          [line for line in listing if len(line) > 72], [])
    names = r.output.split()
    check("WORDS: newest first, truncated names marked",
          [n for n in ("[']", "WOR__", "DUP", "?BR____", "EXI_")
           if n not in names], [])
    check("WORDS: oldest last", names[-3:], ["EXI_", "ok", "bye"])

    print(f"\n{'FAILED' if failures else 'OK'}: {failures} failure(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
