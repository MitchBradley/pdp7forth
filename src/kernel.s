" PDP-7 Forth -- kernel skeleton
"
" Assembling cut at the pieces DESIGN.md settles: NEXT, the CAL trap
" handler ("nest"), dictionary search ("find"), stack pops, EXIT, and
" the flow-control runtime words (BRANCH, ?BRANCH, (DO), (LOOP), I).
" This is not a running Forth yet -- there is no text interpreter and no
" ":"/";" compiler, so the test threads at the end are built by hand.
"
" From the pdp7forth repo root: "make" assembles to build/kernel.lst;
" "make test" runs the smoke tests below under SimH (test/run_tests.py).
"
" DESIGN.md's Implementation notes section records the judgement calls
" this needed (header tag numbering, SIXBIT name packing, the pop
" convention, and EXIT as an ordinary primitive rather than a new tag),
" all confirmed by Mitch.
"
" Register conventions, per DESIGN.md:
"   IP = auto-index register 10
"   RP = auto-index register 11   (return stack, grows up)
"   SP = auto-index register 12   (data stack, grows up)
" Auto-index registers 10-17 pre-increment on indirect reference, so each
" register's own cell must hold (first-slot-address - 1) before its first
" indirect use -- otherwise the pre-increment walks off into whatever
" happens to be at address 1.
"
" NOTE on manifest constants: this machine has no AND/TAD-immediate form.
" "and cmask" means AC := AC AND M[cmask] -- cmask must be the ADDRESS of
" a cell holding the mask, never a bare assembler "=" value substituted
" into the instruction word. Every mask/offset used as an operand to a
" value-fetching instruction (lac/tad/and/sad/xor) below is therefore a
" labelled data cell, per the dNNN/oOOO convention in misc/asm_syntax.txt.

" NOTE on number bases: as7 parses a bare literal starting with a digit
" 1-9 as DECIMAL; only a LEADING ZERO makes it octal (see
" misc/asm_syntax.txt). Every octal register/address literal below is
" therefore written with a leading zero (010, not 10), even where that
" looks redundant, to avoid silently landing on the wrong location.

.=010

" --- reserved low memory: auto-index register cells ---
0		" 010: IP -- set by cold-start "start" below before use
rstack-1	" 011: RP -- primed so the first "dac i 011" lands at rstack
dstack-1	" 012: SP -- primed so the first "dac i 012" lands at dstack
0		" 013: free
0		" 014: free
0		" 015: free
0		" 016: free
0		" 017: free

0		" 020: CAL's return-address slot (hardware-managed, unused here)

" --- nest: entered via the hardware CAL trap (JMS 20 -> here) ---
" DESIGN.md Threading section, transcribed directly.
nest:	lac 010		" IP -> the CAL cell just executed
	dac i 011	" push IP on the return stack (RP = auto-index 11)
	dac t
	lac i t		" cell = body address (tag 00, "CAL -- bare address")
	tad m1		" back up one for NEXT's pre-increment
	dac 010
	jmp next

t:	0		" nest's scratch cell
m1:	-1		" manifest constant: decimal -1

" --- NEXT: the inner interpreter ---
" DESIGN.md Threading section, transcribed directly. Only LAC/LAW-tag
" cells fall through to "dac i 12"; CAL/JMP-tag cells transfer control
" elsewhere (to nest, or into a primitive) and never reach it.
next:	xct i 010	" pre-increment IP, execute the thread cell
	dac i 012	" push AC (only reached by constant/variable cells)
	jmp next

" --- pop.rp / pop.sp: pop the return / data stack ---
" Auto-index registers only pre-increment, so push (already used by
" nest and NEXT above, growing up) gets that for free; pop is the manual
" half DESIGN.md flagged as open. Convention: save the register's
" current value (the address of TOS) in a scratch cell, decrement the
" register, then read the popped value back through the saved pointer
" (a plain, non-incrementing indirect reference, exactly like nest's use
" of "t" above). Impure JMS convention, as with find: returns the popped
" value in AC.
pop.rp:	0
	lac 011
	dac t2
	tad m1
	dac 011
	lac i t2
	jmp i pop.rp

pop.sp:	0
	lac 012
	dac t2
	tad m1
	dac 012
	lac i t2
	jmp i pop.sp

t2:	0		" pop.rp/pop.sp's scratch cell

" --- find: dictionary search ---
" DESIGN.md Dictionary/headers section, transcribed directly, using
" single-digit relative labels (as7's Nf/Nb convention) so the internal
" loop/chk/next/notfnd/found labels don't collide with the kernel's own
" "next" label. Impure JMS convention: call with "jms find" after setting
" tcnt/tname; returns via "jmp i find" with AC = body address, or AC = -1
" if the name isn't in the chain rooted at "latest".
find:	0
	lac latest
1:	dac p
	dac 010
	lac i p
	and cmask	" count field only
	sad tcnt	" skip if count differs
	jmp 2f
3:	lac i p
	and lmask	" link field only
	sna		" 0 = end of chain
	jmp 4f
	cma		" -(dist-1)-1 = -dist
	tad p
	jmp 1b
2:	lac i 010	" name word at p+1
	sad tname
	jmp 5f
	jmp 3b
4:	lac m1		" not found
	jmp i find
5:	lac p		" found: body = p+2
	tad d2
	jmp i find

p:	0
tcnt:	0		" caller sets: count field of the name being sought
tname:	0		" caller sets: packed name word being sought
cmask:	0760000		" manifest constant: count-field mask
lmask:	0000777		" manifest constant: link-field mask
d2:	2		" manifest constant: decimal 2

" --- header tag field values (see DESIGN.md) ---
" These sit only in header-word arithmetic below, never as an instruction
" operand, so plain assembler variables (not data cells) are correct here.
tag.colon=	0
tag.prim=	001000

latest:	h.go		" head of the dictionary chain

" === Kernel dictionary ===
" Primitive bodies end with "jmp next". Branch-type words take an
" inline cell holding (target - 1), which goes straight into IP.

" EXIT: an ordinary primitive, not a spare tag (DESIGN.md, Stacks).
h.ex:	0100000 tag.prim 0		" count=4, link=0: oldest entry
	0457051				" 'EXI'
ex.body:
	jms pop.rp	" AC := the caller's CAL-cell address, pushed by nest
	dac 010		" IP := that address directly -- no "tad m1" here,
			" unlike nest: EXIT resumes the cell *after* the
			" call, nest enters the callee's body
	jmp next

" BRANCH ( -- ): IP := inline cell.
h.bran:	0140000 tag.prim h.bran-h.ex-1	" count=6
	0426241				" 'BRA'
bran:	lac i 010	" fetch the inline (target - 1)
	dac 010
	jmp next

" ?BRANCH ( flag -- ): branch if flag is zero, else skip the inline cell.
h.qbran: 0160000 tag.prim h.qbran-h.bran-1	" count=7
	0374262				" '?BR'
qbran:	lac 012		" inline pop (DESIGN.md, Stacks)
	dac t2
	tad m1
	dac 012
	lac i t2	" flag
	sna		" nonzero (true): fall through
	jmp bran	" zero: take the branch
	isz 010		" step over the inline cell (IP is never 0: no skip)
	jmp next

" (DO) ( limit index -- ) ( R: -- limit index-limit )
" The top return-stack cell is a counter that (LOOP) ISZes up to 0.
h.xdo:	0100000 tag.prim h.xdo-h.qbran-1	" count=4
	0104457				" '(DO'
xdo:	jms pop.sp	" index
	dac t3
	jms pop.sp	" limit
	dac i 011	" R: limit
	cma		" -limit-1
	tad t3
	tad d1		" index - limit
	dac i 011	" R: counter
	jmp next

" (LOOP) ( -- ) ( R: limit counter -- | limit counter+1 )
" Bump the counter in place; branch back via the inline cell until it
" reaches 0, then drop both return-stack cells and skip the inline cell.
h.xloop: 0140000 tag.prim h.xloop-h.xdo-1	" count=6
	0105457				" '(LO'
xloop:	lac 011
	dac t2
	isz i t2	" counter++; skips when it reaches 0
	jmp bran	" not done: loop back
	lac 011
	tad m1
	tad m1
	dac 011		" drop limit and counter
	isz 010		" step over the inline cell
	jmp next

" I ( -- index ): limit + counter.
h.xi:	020000 tag.prim h.xi-h.xloop-1	" count=1
	0510000				" 'I  '
xi:	lac 011		" RP -> counter
	dac t2
	tad m1
	dac t3		" -> limit
	lac i t2
	tad i t3
	dac i 012
	jmp next

t3:	0		" scratch for (DO) and I
d1:	1

" === Test-only words and threads (driven by test/run_tests.py) ===

" BYE: a primitive that pushes a marker. Per DESIGN.md's Threading
" consequences, TOS is not cached in AC, so a result must be pushed to
" survive the next primitive call.
h.bye:	060000 tag.prim h.bye-h.xi-1	" count=3
	0427145				" 'BYE'
bye.body:
	lac byemark
	dac i 012
	jmp next
byemark:
	0123456

" GO: a colon word whose thread is BYE EXIT.
h.go:	040000 tag.colon h.go-h.bye-1	" count=2
	0475700				" 'GO '
go.body:
	jmp bye.body
	jmp ex.body

" Test 1: a CAL cell into GO, which returns here through EXIT.
cboot:	go.body
halt1:	hlt
bootip:	cboot-1

start:	lac bootip
	dac 010
	jmp next
" Expected: halts at halt1 with dstack[0] = 0123456 and RP back at empty.

" Test 2: find. The runner deposits tcnt/tname, then starts here.
" Expected: AC = the word's body address, or 777777 (-1) if not found.
ftest:	jms find
	hlt

" Thread runner: the runner deposits (thread - 1) into tip, then starts
" at trun. Each test thread ends with a hlt cell.
tip:	0
trun:	lac tip
	dac 010
	jmp next

" Constants that test threads push with LAC-tag cells.
d0:	0
d3:	3
d5:	5
d7:	7
o111:	0111
o222:	0222

" ?BRANCH on false: branches over the 111 push.   Expected stack: 222
tqf:	lac d0
	jmp qbran
	1f-1
	lac o111
1:	lac o222
	hlt

" ?BRANCH on true: falls through.   Expected stack: 111 222
tqt:	lac d1
	jmp qbran
	1f-1
	lac o111
1:	lac o222
	hlt

" BRANCH: unconditional.   Expected stack: 222
tbr:	jmp bran
	1f-1
	lac o111
1:	lac o222
	hlt

" 5 0 DO I LOOP   Expected stack: 0 1 2 3 4
tlp0:	lac d5
	lac d0
	jmp xdo
1:	jmp xi
	jmp xloop
	1b-1
	hlt

" 7 3 DO I LOOP   Expected stack: 3 4 5 6
tlp3:	lac d7
	lac d3
	jmp xdo
1:	jmp xi
	jmp xloop
	1b-1
	hlt

.=0500
rstack:	.=.+010		" 8-word return stack

.=0510
dstack:	.=.+010		" 8-word data stack
