# PDP-7 Forth — Design Notes

Goal: a rudimentary but running Forth that fits in the 8K 18-bit words of a PDP-7.

Status markers: **[decided]** = settled by Mitch; **[proposed]** = worked out in discussion, not yet confirmed; **[open]** = unresolved.

## Machine facts driving the design

- 18-bit words, 8K core; memory-reference instructions are 4-bit opcode + 1 indirect bit + 13-bit address.
- Auto-index registers at 10–17 (octal) pre-increment when used indirectly.
- Single accumulator (AC) plus Link; MQ only with EAE. EAE is assumed **[decided]**.
- JMS stores the return address in the target word and jumps to target+1 (not reentrant).
- Indirection is single-level and uses only the low 13 bits of the pointer word.
- TAD is two's complement add; ADD is ones' complement.
- CAL behaves as `JMS 20` independent of its address field. **Verify against the manual for the target machine.**

## Dictionary / headers

**[decided]**
- Single vocabulary. No multiple wordlists.
- No smudge bit. `:` builds the header but LATEST is not updated until `;`, which hides the word being defined.
- Names: count plus the first 3 characters, in 6-bit characters (input is case-folded).
- Link is relative with a 512-word span. That buys 4 bits: 1 immediate bit and 3 tag bits.
- No DOES> words.

Layout:

```
word 0:  [count:5][imm:1][tag:3][link:9]
word 1:  [c1:6][c2:6][c3:6]
word 2:  body (primitive code, colon thread, constant value, variable data)
```

**[proposed]** Link encoding and search:
- Store the link as (distance − 1). Then `CMA` followed by `TAD p` gives `p − distance`, with no extra add.
- A header plus its body is at least 3 words, so a stored link of 0 cannot occur and marks end-of-chain.
- Names shorter than 3 characters are padded with 00 (SIXBIT space).

```
loop,  dac p
       dac 10
       lac i p
       and cmask      / 760000, count only
       sad tcnt       / skip if count differs
       jmp chk
next,  lac i p
       and lmask      / 000777
       sna            / 0 = end of chain
       jmp notfnd
       cma            / -(dist-1) - 1 = -dist
       tad p
       jmp loop
chk,   lac i 10       / name word at p+1
       sad tname
       jmp found      / body = p+2
       jmp next
```

Consequence: the gap between consecutive headers must be ≤ 512 words, which limits ALLOT and very long code bodies. `CREATE` and `:` should detect an out-of-range gap and abort with a message.

## Threading

**[decided]** Essentially ITC, but the code field is implied by tag bits in each thread cell rather than stored in the body.

**[proposed]** The tag is the opcode field, so each thread cell is an executable instruction and NEXT is one instruction:

```
next,  xct i 10       / IP = auto-index 10; pre-increment, execute the cell
       dac i 12       / push AC (SP = auto-index 12); only LAC/LAW cells reach here
       jmp next
```

| Header tag | Cell (opcode) | Meaning |
|---|---|---|
| colon | `00` CAL — bare address | colon word; traps to nest at location 21 |
| primitive | `60` JMP code | machine-code word |
| constant | `20` LAC body | push the constant's value; also used for pooled literals |
| variable | `76` LAW body | push the address (CREATE'd words too) |
| (4 spare) | | |

Compiling: the cell is `optab[tag] | (p+2)`, using an 8-entry table indexed by the header tag.

Nest (at location 21):

```
21,    lac 10         / IP -> the CAL cell
       dac i 11       / push IP (RP = auto-index 11)
       dac t
       lac i t        / cell = body address (tag 00)
       tad m1         / back up one for the pre-increment
       dac 10
       jmp next
```

Consequences of this scheme:
- TOS is not cached in AC. The XCT loads AC before the old TOS could be saved.
- Primitives end with `jmp next` rather than inlining the XCT, because a fall-through must land at `next`.
- A literal compiles as `LAC pool-entry`: one cell, with duplicate values sharing a pool word.
- A constant costs its header plus one word; each use costs one cell.
- LAW pushes the address with its top 5 bits set (effectively addr − 8192). `@` and `!` still work, since indirection uses only the low 13 bits. Printing a raw address, or comparing addresses from different sources, will see the negative form.

## Stacks

**[decided]**
- IP, RP and SP live in auto-index registers 10, 11 and 12. Both stacks grow up.
- Push is the free direction: `dac i 11` / `dac i 12` pre-increments, then stores. Each register starts at (first slot − 1).
- Pop is the manual direction: save the register (the address of TOS) in a scratch cell, decrement the register, then read the value through the saved pointer with a plain indirect.

```
pop.sp, 0
        lac 12
        dac t2
        tad m1
        dac 12
        lac i t2      / AC = popped value
        jmp i pop.sp
```

- Each stack is 32 words, statically allocated below the dictionary. Primitives do no underflow or overflow checks; the interpreter checks depth once after each line.
- EXIT is an ordinary primitive-tag word, not a spare tag. Every tag's cell is one instruction, and EXIT needs several, so a dedicated tag would still have to JMP to shared code. Its body is `jms pop.rp; dac 10; jmp next`. There is no `tad m1`, unlike nest: the popped value is the address of the caller's CAL cell, and NEXT's pre-increment resumes at the cell after it.

## I/O

**[decided]**
- Console teletype only, polled with interrupts off: `ksf`/`krb` in, `tsf`/`tls` out.
- 7-bit ASCII. Input strips bit 8, since a real Model 33 sends it set.
- Case folding happens only on dictionary lookup (and on number digits past 9).
- Paper-tape reader as a second input source (below). No punch yet.

As built (not separately confirmed):
- The kernel echoes input; SimH needs `set tti fdx` so it doesn't echo too.
- CR ends a line and isn't echoed, so " ok" lands on the same line.
- Rubout and backspace drop the last character and echo a backspace.
- The TIB holds 80 characters, one per word. Characters past 80 are ignored.

## Paper tape input

**[decided]**
- TAPE switches `accept`'s input from the keyboard to the paper-tape reader; SimH backs the reader with a host file (`attach ptr file`). Tape lines echo, as an ASR-33 prints tape as it reads it.
- ^D (EOT, 004) ends tape input and returns to the keyboard. Mid-line it also ends that line. The tools append it (`tools/mktape.py`), so source files stay ordinary text.
- The word EOT is a visible alternative to ^D in source files: it ends tape input, and the rest of its line is ignored.
- ^D typed at the keyboard halts, like BYE.
- The prelude build mounts the prelude (plus BYE) as a tape instead of typing it at the console.

As built (not separately confirmed):
- On tape, NUL frames (blank leader and trailer) and CR are skipped, and LF ends a line, so LF and CR LF files both work.
- ^D at the start of a line just switches to the keyboard, so a file ending in LF then ^D doesn't produce an extra empty `ok` line.
- EOT typed at the keyboard just ignores the rest of the line.
- After a ^D halt from the keyboard, CONTINUE resumes and the ^D is then treated like one from tape (it ends a partly typed line).
- An error while reading tape stops tape input (abort returns to the keyboard), so the rest of a broken file isn't interpreted. The reader keeps its position, so a later TAPE resumes after the failing line. A cold start also resets input to the keyboard.
- The reader is program-paced (`rsa` asks for one frame; `rsf`/`rrb` wait for and read it), so unlike the keyboard it can't overrun.
- The PDP-7 has no reader-empty status bit (the PDP-9 and PDP-15 do). A tape with no ^D leaves the kernel waiting for more tape, as it would when real tape runs out; SimH's reader STOP_IOE register can make it halt with "PTR end of file" instead.

## Graphics

**[decided]**
- The display is the Type 340, as emulated by Open SIMH (SimH 3.8 has none; its display IOTs are no-ops, so graphics code runs there invisibly). The 340 is a display processor: `700604` loads its address counter from AC and starts it, and it runs a display list from core until a stop; `700601` skips if it has stopped.
- The kernel reserves a 1024-word display list, DLIST, below 4K (the 340's address counter is 12 bits). It sits before the dictionary headers, because a header can't link across it (the 512-word span).
- Refresh: while waiting for a key, `getc` restarts the 340 at DLIST whenever the variable DISPLAY is set and the 340 has stopped. The picture stays lit at the keyboard and fades during long computations.
- Turtle graphics lives in `lib/turtle.fs`, loaded with TAPE: FORWARD/FD, BACK/BK, RIGHT/RT, LEFT/LT, PENUP/PU, PENDOWN/PD, HOME, CLEARSCREEN/CS, with Logo's conventions. Angles are degrees, through a 91-entry sine table (sin × 16384).
- `*/` is in the kernel, using the EAE's 36-bit MUL and DIV, so `n × sine` can't overflow before the divide.

As built (not separately confirmed):
- Display list: a parameter word (point mode, scale 1, full intensity), point words setting X and Y, then one vector word per step of at most 127 pixels, then the turtle, then an escaping vector and a stop. Appending writes the new terminator before the word that replaces the old one, since the 340 may be running the list.
- The turtle's position is kept in 1/64 pixel, so rounding doesn't accumulate; a move becomes N vector steps whose sizes add up exactly.
- A move that would leave the 1024 × 1024 screen is refused (`off screen?`), since a vector hitting the edge would make the 340 escape to parameter mode and misread the rest of the list. A full list refuses further drawing (`display list full?`). Both then QUIT.
- CLEARSCREEN homes the turtle and starts a new list; HOME draws if the pen is down, as in Logo.
- The turtle is drawn as a triangle at the end of the list, after the path, where the beam is: an invisible vector to its nose (15 pixels along the heading), then three sides to back corners 8 pixels out at ±150°. It's rewritten, with the terminator, after every move, turn and CLEARSCREEN, so it's missing only while a move is in progress. It's left out within 15 pixels of the screen edge, where one of its vectors could hit the edge. HIDETURTLE/HT and SHOWTURTLE/ST turn it off and on.
- `cold` runs the 340 once over the list's initial stop word, because until it has run once it doesn't report "stopped".
- Open SIMH's pdp7 enables G2OUT (the Graphics-2, pdp7-unix's second terminal) at device 05, which conflicts with the 340; `make run GRAPHICS=1` disables it and enables DPY.
- Open SIMH can `screenshot` its display with SDL's dummy video driver, so `make test PDP7_DISPLAY=...` checks an actual drawing.

## Memory

**[decided]**
- Low memory: auto-index registers 10–17, CAL slot at 20, nest at 21, then the kernel, the two stacks, and the TIB. The dictionary grows up from there (`dp`).
- Literals live in a pool that grows down from the top of memory (`pool`). Compiling a literal searches the pool for an equal value before adding one. Free space is the single gap between `dp` and `pool`.
- No FORGET, so the pool never has to shrink.

## Numbers and arithmetic

**[decided]**
- BASE defaults to decimal.

As built (not separately confirmed):
- `number` accepts an optional leading `-`; digits past 9 are letters in either case, up to base 36.
- EAE's signed MULS/IDIVS assume ones'-complement signs (−6 × 7 gives the ones' complement of 5 × 7), so they're unusable with two's-complement values. `*` uses unsigned MUL: its low 18 bits are the two's-complement product. `/` and MOD divide magnitudes with unsigned IDIV and fix signs in software, truncating toward zero; the remainder has the dividend's sign.
- Unsigned MUL/IDIV need the link clear first.
- OR has no instruction; it's `(a^b) ^ (a&b)`.
- `<` flips both sign bits and uses the unsigned compare, which reads the carry from `b + ~a` out of the link.

## Flow control

**[decided]**
- BRANCH and ?BRANCH are primitives followed by an inline cell holding (target − 1). With IP in auto-index 10, BRANCH is `lac i 10; dac 10; jmp next`. ?BRANCH pops the flag, jumps to BRANCH's code if it's zero, and otherwise does `isz 10` to step over the inline cell. Each use costs 2 cells, and targets are absolute, so the 512-word link span doesn't limit them.
- No 1-cell branch. No single instruction XCT'd from NEXT can load IP with a constant, so a spare tag doesn't help. `CAL i` jumps through location 20, which every ordinary CAL overwrites.
- Counted loops use ISZ. (DO) takes `limit index` and pushes limit, then a counter of (index − limit), on the return stack. (LOOP) does `isz` on the counter in place and branches back until the counter reaches 0. I is limit + counter.
- The runtime words keep their headers for now. They could be made headerless later, with the compiling words holding their cells as pooled literals, if space runs short.
- Compiling words (not built yet): IF compiles ?BRANCH plus an empty cell and leaves its address. THEN stores `HERE 1-` there. BEGIN/UNTIL/AGAIN/WHILE/REPEAT/ELSE follow the usual pattern with the same target − 1 convention.
- Deferred: `+LOOP` (needs a real add and a sign-crossing test instead of ISZ), `?DO`, LEAVE, UNLOOP.

## Execution tokens and the interpreter

**[decided]**
- An xt is a header address. `find` returns it (or −1), and `'` pushes it.
- `mkcell` turns an xt into the thread cell that calls it: `optab[tag] | (xt + 2)`. The compiler (`COMPILE,`) and EXECUTE share it.
- EXECUTE builds that cell in a scratch location followed by an EXIT cell, pushes IP, and points IP at the scratch cell. This works for every tag. A nested EXECUTE can overwrite the scratch cell safely, because the outer one has already been read by then.

As built (not separately confirmed):
- `find` uses auto-index 013 rather than 10 as in the sketch above: it runs inside primitives, where 10 is IP.
- The outer interpreter is a thread (`qthr`) over primitives (QUERY), (PARSE), (FIND), (NUMBER), (OK) and (ERR), which keep their headers like every other word. A found word is compiled if STATE is set and the word isn't immediate; otherwise it's executed. A number is compiled as a pooled literal when STATE is set.
- `:` lays down the header but only `;` links it into LATEST (no smudge bit). `CONSTANT`, `VARIABLE` and `CREATE` link immediately.
- Errors print the offending token and a message (`?`, `name?`, `far?`, `full?`; there's no stack checking), then abort: a definition in progress is discarded by resetting `dp` to its header, both stacks are emptied, and STATE returns to 0. `;` outside a definition is an error.
- `:` checks the relative-link span and the 31-character name limit when it builds a header. ALLOT and `,` check for the literal pool.
- `.` prints signed in BASE, digits past 9 as upper-case letters, then a space.
- Also built: `COMPILE,`, LITERAL, `,`, HERE, ALLOT, STATE, `[`, `]`, IMMEDIATE, the compiling control words, `(` and `\` comments, CR, QUIT, and BYE (halts; CONTINUE resumes).
- J is a primitive, like I: the enclosing loop's cells are right under the inner loop's on the return stack.

## Interpretive control structures

**[decided]** (Mitch's invention, as in Open Firmware)
- IF, BEGIN and DO used while interpreting start compiling into a scratch buffer, counting nesting levels. When the outermost structure closes (THEN, UNTIL, AGAIN, REPEAT, LOOP), the compiled code runs at once and is discarded, and interpretation carries on with the rest of the line. A structure can span lines. Inside a colon definition nothing changes.

As built (not separately confirmed):
- The scratch buffer is 100 words in the kernel, not HERE, so the code can compile or ALLOT into the dictionary (`3 0 DO I , LOOP`) without overwriting itself. `dp` points into it while compiling and is restored before the code runs.
- It runs through EXECUTE's machinery: its bare address is a CAL cell.
- An error, or overflowing the buffer (`full?`), discards the structure and restores `dp`.
- Literals compiled into it still go to the literal pool, which never shrinks, so each new literal value used interpretively costs a pool word.

## Prelude and strings

**[decided]**
- Words that are easy to write in Forth live in `src/prelude.fs`. At build time `tools/prelude.py` boots the kernel under SimH, types the prelude at it, and saves memory as the image (`build/forth.img`). The source text takes no space on the target. A prelude line that doesn't answer ` ok` fails the build.
- Kernel messages and `."` strings are packed two 9-bit characters per word, ended by a zero word (so a zero half-word is skipped on output). `."` compiles `(.")` followed by the string inline; `(.")` prints it and resumes after the terminator.
- Character-addressed strings (S", TYPE, COUNT, C@ and friends) are one character per word, so a character address is a cell address. C@ and C! are @ and !, and CHAR+ is 1+. That spends space for simplicity: no half-word addressing, and a string can be handled with ordinary cell words.
- S" while interpreting copies the string into a kernel buffer (sbuf, 80 words, before the dictionary) and pushes c-addr u. The next interpreted S" overwrites it. While compiling, including inside an interpretive control structure, it compiles `(S")`, a count cell, and the characters inline; `(S")` pushes c-addr u and resumes after them.

As built (not separately confirmed):
- The prelude defines TRUE FALSE BL DECIMAL HEX OCTAL 1+ 1- CELL+ ?DUP NIP TUCK ROT -ROT 2DUP 2DROP > <> 0> 0<> ABS MIN MAX +! SPACE SPACES ['].
- There's no CELLS: a cell is one word, and CELLS would collide with CELL+ (same length and first three characters, which is all a header stores).
- The kernel has `(S")`, S", CHAR and `.(`. The prelude adds C@ C! C, CHAR+ COUNT TYPE [CHAR]. There's no CHARS (a no-op here), which would collide with CHAR+.
- A string that reaches the end of the line without a closing `"` ends there, for S" as for `."`.

## Name collisions and WORDS

**[decided]**
- Defining a name whose length and first three characters match an existing word prints `<name> redefined` and goes ahead; the new word hides the old one. This covers `:`, CONSTANT, VARIABLE and CREATE. The prelude build fails on the warning (and `tools/prelude.py` also checks names against the kernel source before running anything).
- WORDS lists the dictionary newest first.

As built (not separately confirmed):
- WORDS prints the stored characters of each name, then one underscore per character that wasn't stored (`EXIT` shows as `EXI_`), so the listing shows each name's true length. It starts on a new line and breaks lines at about 60 columns, since a Model 33 doesn't wrap.
- `."` always compiles. That works in a definition or an interpretive control structure; typed bare at the prompt it lays the string down in the dictionary, unused. Use `.(` there instead: it's immediate and prints up to the next `)` at once. S" works either way.

## Open issues

- **[open]** Uses for the 4 spare tags. (EXIT does not use one; see Stacks.)

## Implementation notes

`src/kernel.s` holds the whole kernel: NEXT, nest, `find`, the stack
helpers, the outer interpreter and compiler support, the display list,
and the kernel's dictionary. `src/end.s` must be assembled last; its
label marks the start of free space (currently 04756, about 2,500
words, 1K of it the display list).

`make` builds `build/forth.img` (kernel plus compiled prelude) and a
SimH script for it; `make run` boots it in SimH (`pdp7`), and
`make run TAPE=file.fs` also mounts a file in the reader for TAPE;
`make test` runs
`test/run_tests.py`, which assembles the kernel with `test/tests.s`
(test-only drivers and hand-built threads), reads addresses from the
listing, and checks results under SimH with console input piped in.
Besides unit checks on each primitive, it runs scripted interactive
sessions on an image with the prelude compiled in, and compares the
exact transcripts.

`tools/simh.py` drives SimH for the prelude build and the tests. Its
console is a pseudo-terminal, not a pipe: SimH 3.8 polls a non-tty
stdin with a blocking `read()`, which freezes the whole simulator,
output included, until input arrives, and then delivers that input
while the program is busy, so characters were lost. It also waits for
SimH to enter run mode before typing, since SimH flushes pending input
then. SimH's keyboard still takes the next character every TTI `TIME`
instructions whether or not the program has read the last one; the
tools set a Model 33's rate (10 characters per second ≈ 30,000 PDP-7
instructions) and wait for each line's ` ok` or `?` before typing the
next, like a person at the teletype. Real hardware could overrun the
same way if input came faster than the kernel reads it, for example
from a paper-tape reader. `tools/hdr.py` prints the
two header words for a name.

`as7`'s `rim` and `ptr` output formats only dump memory from the
relocation base (4096) up, so they produce an empty tape for this
low-memory layout. The test runner and `make run` deposit the `a7out`
dump directly instead. A paper-tape image will need either a loader or
code above 4096.

Header tag numbering (colon=0, primitive=1, constant=2, variable=3,
4–7 spare) and SIXBIT name packing (`ascii(ch) − 040`) are
**[decided]**.

`as7` gotchas, all easy to hit silently:
- A literal with no leading zero is *decimal*: `10` is ten. Octal
  values are written `010`.
- Space-separated terms are ORed, not added. Header words must use `+`
  (`0060000+tag.prim+h.key-h.emit-1`), since addresses overlap the tag
  bits.
- Labels are truncated to 8 characters.
- Built-in symbols shadow labels of the same name: opcodes, EAE
  mnemonics such as `divs` and `abs`, and Unix system call names such as
  `exit`, `read` and `write`.
- Character literals are `<a>b`: `<a` is the high 9 bits, `>b` the low.

## Idea stack (deferred)

- Token threading with two 9-bit tokens per word: roughly halves thread size, at the cost of a table lookup in NEXT and a 512-token limit.
- Aligning headers on 2-word boundaries so the link's low bit is always zero and can serve as a flag. Superseded for now by the 512-word span, which already bought the needed bits.
- Separating heads from bodies so headers can be discarded in a turnkey image.
- A zero-count dummy header (it never matches) to bridge gaps over 512 words, if the ALLOT limit becomes a problem.
