"""Drive SimH's pdp7 with a kernel image and a paced console.

The console is a pseudo-terminal, not a pipe: SimH 3.8 polls a non-tty
stdin with a blocking read(), which freezes the whole simulator (output
included) whenever no input is waiting, then delivers input while the
program is busy. On a tty it switches to non-blocking reads.

SimH's keyboard still takes the next character every TTI TIME
instructions whether or not the program has read the last one, so
Sim.type() waits for each line's response before sending the next, like
a person at the teletype, and TTI_TIME sets a Model 33's rate (10
characters/second is about 30,000 PDP-7 instructions).
"""
import os
import pty
import re
import subprocess
import termios
import tempfile
import threading
import tty
import time

MASK = 0o777777
TTI_TIME = 30000
RESPONSE_END = re.compile(rb"(ok|\?)\r\n$")
BANNER = re.compile(r"PDP-7 simulator V[\d.\-]+\n")


class Sim:
    def __init__(self, image, start, deposits=(), examine=(), setup=()):
        cmds = ["set cpu 8k", "set cpu eae", "set tti fdx", "set tti 8b",
                f"d tti time {TTI_TIME}"]
        cmds += list(setup)
        cmds += [f"d {a:o} {w & MASK:o}" for a, w in image]
        cmds += [f"d {a:o} {w & MASK:o}" for a, w in deposits]
        cmds.append(f"go {start:o}")
        cmds.append("examine ac")
        cmds += [f"examine {a:o}" for a in examine]
        cmds.append("exit")
        fd, self.script = tempfile.mkstemp(suffix=".do")
        with os.fdopen(fd, "w") as f:
            f.write("\n".join(cmds) + "\n")
        self.tty, slave = pty.openpty()
        tty.setraw(slave)  # no line editing or echo before SimH sets it
        self.proc = subprocess.Popen(["pdp7", self.script], stdin=slave,
                                     stdout=subprocess.PIPE)
        os.close(slave)
        self.running = False
        self.buf = b""
        self.lock = threading.Lock()
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.reader.start()

    def _read(self):
        while True:
            chunk = os.read(self.proc.stdout.fileno(), 4096)
            if not chunk:
                return
            with self.lock:
                self.buf += chunk

    def _wait_running(self, timeout=10):
        """SimH switches the tty to run mode with TCSAFLUSH, discarding
        anything typed before then. Run mode sets VMIN to 0; ours is 1."""
        deadline = time.monotonic() + timeout
        while termios.tcgetattr(self.tty)[6][termios.VMIN] != 0:
            if time.monotonic() > deadline or self.proc.poll() is not None:
                raise RuntimeError("SimH never started running")
            time.sleep(0.002)
        self.running = True

    def send(self, text):
        if not self.running:
            self._wait_running()
        os.write(self.tty, text.encode("latin-1"))

    def type(self, line, timeout=2.0):
        """Send a line, then wait until it answers ok or ?. Lines with no
        such answer (QUIT, an unfinished definition) wait out the timeout."""
        with self.lock:
            mark = len(self.buf)
        self.send(line + "\r")
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            with self.lock:
                if RESPONSE_END.search(self.buf[mark:]):
                    return
            time.sleep(0.002)

    def finish(self, tail="", timeout=30):
        """Send tail, end input, and wait for the halt. Returns (console
        output, {"ac": AC, addr: word, ...})."""
        if tail:
            self.send(tail)
        try:
            self.proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            raise RuntimeError("timed out; console so far:\n"
                               + self.buf.decode("latin-1")) from None
        finally:
            os.unlink(self.script)
            os.close(self.tty)
        self.reader.join()
        out = self.buf.decode("latin-1")
        if "HALT instruction" not in out:
            raise RuntimeError(f"did not halt:\n{out}")
        values = {}
        for m in re.finditer(r"^(\w+):\s+([0-7]+)$", out, re.M):
            key = m.group(1)
            values["ac" if key == "AC" else int(key, 8)] = int(m.group(2), 8)
        console = BANNER.sub("", out)
        console = console[:console.index("\nHALT instruction")]
        if console.endswith("\n"):  # SimH's, before its HALT message
            console = console[:-1]
        return console, values
