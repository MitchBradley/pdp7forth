#!/usr/bin/env python3
"""Draw a turtle picture on the emulated Type 340 and save it as a PNG.

usage: screenshot.py LISTING IMAGE OUTPUT.png

Needs an Open SIMH pdp7 with display support (PDP7=path). Uses SDL's
dummy video driver, so no window opens.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mktape  # noqa: E402
import prelude  # noqa: E402
import simh  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DRAWING = [
    ": sq 4 0 do 180 fd 90 rt loop ;",
    ": flower 12 0 do sq 30 rt loop ;",
    "flower",
]


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    listing, image, out = sys.argv[1:]
    labels = prelude.read_labels(listing)
    turtle = open(os.path.join(ROOT, "lib/turtle.fs")).read()
    out = os.path.abspath(out)
    if os.path.exists(out):
        os.unlink(out)
    os.environ["SDL_VIDEODRIVER"] = "dummy"
    sim = simh.Sim(prelude.read_image(image), labels["cold"],
                   tape=mktape.to_tape(turtle),
                   setup=["set g2out disabled", "set g2in disabled",
                          "set dpy enabled"],
                   after=[f"screenshot {out}"])
    sim.type("tape")
    sim.wait_for(rb"pendown clearscreen  ok\r\n", timeout=120)
    for line in DRAWING:
        sim.type(line, timeout=20)
    sim.finish("bye\r")
    if not os.path.exists(out):
        sys.exit("no screenshot: does this pdp7 have display support?")
    print(out)


if __name__ == "__main__":
    main()
