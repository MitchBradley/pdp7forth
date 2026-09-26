# PDP-7 Forth

A small Forth for the DEC PDP-7 (18-bit words, 8K of core), assembled
with the `as7` assembler from [pdp7-unix](https://github.com/DoctorWkt/pdp7-unix)
and run under the [SimH](https://opensimh.org/) PDP-7 simulator.
`DESIGN.md` explains how it works and why.

![A flower of twelve squares drawn by the turtle on the emulated Type 340 display](docs/turtle.png)

## Highlights

- **It runs on the machine Unix was born on.** The PDP-7 has 18-bit
  words, no byte addressing, and 8K words of core. The kernel is PDP-7
  assembly, built with the same assembler the pdp7-unix restoration
  uses.
- **The threading.** Each cell of a colon definition is a PDP-7
  instruction, executed by the inner interpreter with `xct`. A
  definition's type is in the cell's opcode bits: a call is a bare
  address (a CAL), a primitive is a `jmp`, a constant is a `lac` and a
  variable is a `law`. So NEXT is three instructions, and constants and
  variables need no code of their own.
- **Two-word headers.** A header is the name's length, an immediate
  bit, a 3-bit type tag and a 9-bit relative link in one word, and the
  first three characters of the name in the other.
- **Interactive control structures.** IF, DO and BEGIN work at the
  prompt, not just inside definitions.
- **Turtle graphics** on the PDP-7's Type 340 vector display, which
  Open SIMH emulates.
- **Paper tape.** Forth source loads from the emulated paper-tape
  reader, backed by a file on your computer.
- **A prelude compiled at build time.** Words written in Forth are
  compiled into the memory image by running the kernel under SimH, so
  their source takes no space on the PDP-7.

### Size

The kernel, including its headers, is about 1.5K words of code and
data. It also holds a 1K-word display list, the stacks and some
buffers, and ends at 05422 (octal), about 2.8K words. The prelude adds
about 200 words. That leaves about 5,150 words, nearly two thirds of
memory, for your definitions.

## Setup

You need `git`, `make`, `perl` (for `as7`), Python 3, and SimH's
PDP-7 simulator, `pdp7`.

Clone with the pdp7-unix submodule:

```
git clone --recurse-submodules https://github.com/MitchBradley/pdp7forth
cd pdp7forth
```

(In an existing clone, `git submodule update --init` fetches it.)

### SimH

You can run Forth without graphics with a precompiled SimH, but to
use Turtle Graphics, you will need to compile yourself to pick up
the SimH graphics support.

#### Precompiled SimH on Linux

Debian and Ubuntu package SimH 3.8, which you can use:

```
sudo apt install simh
```

Other distributions may package it too. Check that the package gives
you a `pdp7` command; if not, build it from source (below).

#### Precompiled SimH on macOS

Install Apple's command-line tools, which provide `make`, `git` and
Python 3 (`perl` is already there), then Open SIMH from Homebrew:

```
xcode-select --install
brew install open-simh
```

### Building SimH from source (Linux or macOS)

You will need to do this if no package works for you, or if you
want to use Turtle Graphics.

```
git clone https://github.com/open-simh/simh.git
cd simh
make pdp7
```

That leaves the simulator in `simh/BIN/pdp7`. Either put it on your
`PATH` as `pdp7`, or tell this project where it is:

```
make run PDP7=~/simh/BIN/pdp7
```

(`PDP7` works for every target, and for `test/run_tests.py` as an
environment variable.)

The project was tested with SimH 3.8 on Linux, Homebrew's `open-simh`
on macOS, and with Open-SimH compiled from source on Linux and macOS. Windows under WSL should work, but hasn't been
tried.

## Building and testing

```
make          # assemble the kernel, then compile src/prelude.fs into it
make test     # run the test suite under SimH
```

With SimH 3.8 the suite takes a few seconds. Open SIMH is much slower
(several minutes), because it takes most of a second to start and the
suite starts it over a hundred times; it hasn't hung.

`make test PDP7_DISPLAY=path/to/open-simh/pdp7` also checks a turtle
drawing on the emulated display (see Turtle graphics). It's skipped
otherwise.

`make` runs SimH once to compile the prelude, so SimH is needed even
to build.

## Running

```
make run
```

SimH starts the kernel, which prints

```
PDP-7 FORTH
```

and waits for input. Type Forth and press Return; each line answers
` ok`, or names the word it didn't understand with a `?`:

```
2 3 + . 5  OK
: SQ DUP * ; 7 SQ . 49  OK
FOO FOO ?
```

- **Case.** By default SimH behaves like a Model 33 teletype, which only
  has upper case, so input and output appear in upper case. Forth
  itself doesn't care. For lower case, get to the `sim>` prompt (below),
  type `set tti 7b`, then `c` to continue.
- **Editing.** Backspace or Delete erases the last character. There's no
  other line editing.
- **Pasting.** The keyboard runs at about teletype speed, so pasting more
  than a few lines is slow. Load files from paper tape instead (below).
- **Numbers.** A cell is 18 bits, two's complement: -131072 to 131071.
  BASE starts decimal; `HEX`, `OCTAL` and `DECIMAL` change it.
- **Errors** print the word at fault and a message, then abort: `FOO ?`
  for a word that isn't defined and isn't a number, `name?` for a
  missing or over-long name, `full?` when memory is full, and `far?`
  when a header would be too far from the previous one (after a very
  large ALLOT, say). At the end of each line the data stack's depth is
  checked, and underflow or overflow gives `stack?`. The check is per
  line, not per word, so a line that underflows and then pushes enough
  back goes unnoticed.
- **Interactive control structures at the prompt.** IF, DO and BEGIN work
  interactively as well as in definitions: `4 0 DO I . LOOP` runs as
  soon as the LOOP is typed, and a structure can span lines.
- **Strings.** `S" text"` gives a string's address and length, one
  character per word, and `TYPE` prints it: `S" hello" TYPE`. At the
  prompt the string goes into a buffer that the next `S"` reuses; in a
  definition it's compiled in. `CHAR A` and, in definitions, `[CHAR] A`
  give a character's code. `." text"` prints text from a definition;
  at the prompt, use `.( text)`.
- **Looking around.** `WORDS` lists the dictionary. A header keeps only a
  name's length and first three characters, so longer names show as
  those three plus an underscore per missing character (`EXIT` shows as
  `EXI_`). Two names with the same length and first three characters
  are the same word to the dictionary; defining one prints
  `name redefined`.  This length+3 name format is an old-school optimization
  to save space on memory-limited machines.

## The language

Type `WORDS` for the whole dictionary. In brief:

- **Stack and arithmetic:** DUP DROP SWAP OVER ROT -ROT NIP TUCK ?DUP
  2DUP 2DROP >R R> R@ + - * / MOD */ 1+ 1- NEGATE ABS MIN MAX AND OR
  XOR INVERT = <> < > U< 0= 0< 0> 0<> TRUE FALSE
- **Memory:** @ ! +! C@ C! , C, HERE ALLOT CELL+ CHAR+
- **Defining:** : ; CONSTANT VARIABLE CREATE IMMEDIATE
- **Control:** IF ELSE THEN BEGIN UNTIL AGAIN WHILE REPEAT DO LOOP I J
  EXIT
- **Compiler:** ' ['] EXECUTE COMPILE, LITERAL [ ] STATE
- **Output and strings:** . EMIT CR SPACE SPACES TYPE COUNT ." .( S"
  CHAR [CHAR] BL BASE DECIMAL HEX OCTAL KEY
- **Other:** ( \ WORDS QUIT BYE TAPE EOT, and DLIST and DISPLAY for
  graphics

It's a small, mostly standard Forth, with some differences:

- Names are known by their length and first three characters (see
  Looking around, above).
- A character takes a whole cell, so C@ is @ and a character address is
  a cell address.
- `/` and MOD truncate toward zero; the remainder has the dividend's
  sign.
- `."` only compiles; use `.(` at the prompt.
- A definition's name isn't visible until `;`, so a word can't call
  itself (there's no RECURSE), and a redefinition can call the word
  it replaces.
- Not included: DOES>, FORGET, ?DO, +LOOP, LEAVE, POSTPONE, RECURSE,
  `.S`, `U.`, pictured numeric output (`<# # #>`), double-cell numbers,
  CELLS and CHARS, PICK and ROLL, MOVE and FILL, ABORT", EVALUATE, and
  the standard input words (ACCEPT, WORD, `>IN`). There's one
  vocabulary.

## Stopping and exiting

- **`BYE`, or ^D**, halts the PDP-7 and drops you to SimH's `sim>`
  prompt.
- At `sim>`, **`exit`** (or `quit`) leaves SimH. **`c`** (continue)
  resumes Forth where it stopped, with everything you defined intact.
  (If you halted with ^D partway through typing a line, that line ends
  there when you continue.)
- **Ctrl-E** gets to `sim>` at any time, even when Forth is busy or
  stuck. It's SimH's interrupt key.
- **Ctrl-C and Ctrl-Z don't work** while the PDP-7 is running. SimH
  passes Ctrl-C to Forth as an ordinary character, and suspend is off.
  Use Ctrl-E.

While the PDP-7 runs, SimH turns off your terminal's echo and line
editing (Forth does its own). It restores them at `sim>` and on exit. If
SimH is killed instead of exiting (for example `kill -9`, or a dropped
ssh session), the terminal stays in that state, with invisible typing
and stair-stepped lines; `stty sane` or `reset` fixes it.

## Loading source from paper tape

The PDP-7's paper-tape reader is a second input source, and SimH reads
its tape from a file on your computer. `TAPE` switches Forth's input to
the reader; each line is echoed as it's read, like an ASR-33 printing
tape. At the end of the tape, input returns to the keyboard.

The tape must end with a marker. Without one, Forth waits at the end of
the file for more tape, because the PDP-7 can't sense an empty reader.
Either:

- end the file with ^D (character 004). `tools/mktape.py` copies a
  text file and appends one:

  ```
  python3 tools/mktape.py mywords.fs mywords.ptr
  ```

- or make the file's last line the word `EOT`.

Ordinary text files with LF or CR LF line endings work.

### Mounting a file at startup

```
make run TAPE=mywords.fs
```

This appends the ^D for you and mounts the file. Then type

```
TAPE
```
at the Forth prompt to load the file.

### Mounting a file in the middle of a session (the tape trick)

Everything you've defined so far survives:

1. Press ^D (or Ctrl-E) to halt to `sim>`.
2. `attach ptr mywords.ptr` (a file with an end marker, as above).
3. `c` to continue. You're back in Forth.
4. Type `TAPE`.

Each `attach` starts that file from the beginning; attach it again to
reread it.

### When something goes wrong on tape

- An error while reading tape (an undefined word, say) prints the usual
  message and stops tape input, so the rest of the file isn't run with
  a half-built definition. The reader keeps its place, so after fixing
  things by hand, `TAPE` resumes at the next line.
- If Forth is waiting at the end of a tape with no end marker, press
  Ctrl-E, `attach ptr` any file that contains a ^D, and `c`. Forth reads
  the ^D and returns to the keyboard.

## Turtle Graphics

Open SIMH (version 4) emulates the PDP-7's Type 340 display in a window;
SimH 3.8 doesn't have it. Homebrew's `open-simh` does not have the display,
so you will have to build it from source with the SDL2 library installed
(the build output then says "video capabilities provided by libSDL2").
Turtle graphics comes as a Forth source file, `lib/turtle.fs`, loaded
from paper tape.

### Running it

1. From the `pdp7forth` directory, start Forth with the display on and
   the turtle mounted in the tape reader. If your `pdp7` isn't on
   `PATH`, name it with `PDP7=`, for example a source build next to this
   directory:

   ```
   make run TAPE=lib/turtle.fs GRAPHICS=1
   make run TAPE=lib/turtle.fs GRAPHICS=1 PDP7=../simh/BIN/pdp7
   ```

   `GRAPHICS=1` enables the display (and disables the Graphics-2
   device, which otherwise claims the same device number). A display
   window opens alongside your terminal.

2. Keep typing in the terminal: it's the teletype. Load the turtle:

   ```
   TAPE
   ```

   The source echoes as it loads, and a small triangle appears in the
   middle of the window, pointing up.

3. Draw:

   ```
   4 0 DO 200 FD 90 RT LOOP
   : SQ 4 0 DO 200 FD 90 RT LOOP ;
   : FLOWER 8 0 DO SQ 45 RT LOOP ;
   CS FLOWER
   : STAR 5 0 DO 400 FD 144 RT LOOP ;
   CS PU 200 BK 90 LT 200 FD 90 RT PD STAR
   ```

   As the first line shows, interactive control structures let you
   draw without making definitions.

4. Finish with `BYE` (or ^D), then `exit` at the `sim>` prompt.

To also check a drawing on the emulated display in the test suite (no
window opens):

```
make test PDP7_DISPLAY=../simh/BIN/pdp7
```

The picture at the top of this page comes from
`make screenshot PDP7=../simh/BIN/pdp7`, which draws a flower of
squares and saves the display as `docs/turtle.png`.

### The Turtle words

With Logo's conventions (the turtle starts in the middle of
the 1024 x 1024 screen, heading 0 is up, turns are in degrees and RIGHT
is clockwise):

| Word | Short | |
|---|---|---|
| `FORWARD` ( n -- ) | `FD` | move n pixels, drawing if the pen is down |
| `BACK` ( n -- ) | `BK` | |
| `RIGHT` ( degrees -- ) | `RT` | |
| `LEFT` ( degrees -- ) | `LT` | |
| `PENUP` | `PU` | |
| `PENDOWN` | `PD` | |
| `HOME` | | move to the middle, heading up (drawing if the pen is down) |
| `CLEARSCREEN` | `CS` | erase, and go home |
| `HIDETURTLE` | `HT` | stop drawing the turtle |
| `SHOWTURTLE` | `ST` | draw it again |

The turtle is a small triangle pointing along its heading. It isn't
drawn within 15 pixels of the edge of the screen. A move that would
leave the screen is refused with `off screen?`. The
drawing is kept in a display list of 1024 words (roughly a thousand
line segments); when it's full, drawing stops with `display list full?`
until `CLEARSCREEN`.

The picture stays lit while Forth waits at the keyboard, which is when
it restarts the display. During a long computation it fades, as it
would have on the real machine. The drawing words also work, invisibly,
under SimH 3.8.

## Files

- `src/kernel.s`: the kernel in PDP-7 assembly.
- `src/prelude.fs`: words written in Forth, compiled into the image at
  build time.
- `lib/turtle.fs`: turtle graphics, to load with TAPE.
- `DESIGN.md`: design decisions, open issues, and implementation notes.
- `docs/turtle.png`: the picture above (`make screenshot`).
- `test/`: the test suite (`make test`).
- `tools/`: build helpers. `tools/pdp7-unix` is the submodule that
  provides `as7`.
- `CLAUDE.md`: guidance for Claude Code when working on the project.

## Working on it

`DESIGN.md` records each decision and marks it **[decided]**,
**[proposed]** or **[open]**; keep it current along with the code.

```
make test-new # run only the tests for work in progress
```

`make test-new` runs `new_features()` in `test/run_tests.py`, a short
list of tests for whatever is being worked on, so they can be checked
without the full suite. The full suite runs them too; once a feature
settles, move its tests into the main suite.

## Credits

- The project began with an email exchange with Don Hopkins and David
  Rosenthal on 25 September 2026, and was written the next day.
- Warren Toomey (DoctorWkt) and the
  [pdp7-unix](https://github.com/DoctorWkt/pdp7-unix) team wrote `as7`,
  the assembler used here.
- Bob Supnik wrote SimH, and the [Open SIMH](https://opensimh.org/)
  project maintains it, Type 340 display and all.
- The turtle comes from Logo, by Seymour Papert, Wally Feurzeig and
  Cynthia Solomon.

PDP-7 Forth was created by Mitch Bradley with
[Claude Code](https://claude.com/claude-code), using Claude Opus 5.5.

## License

MIT; see `LICENSE`. The pdp7-unix submodule, used only as a build tool,
has its own license (GPL v3).
