" PDP-7 Forth -- kernel skeleton
"
" Assembling cut at the pieces DESIGN.md settles: NEXT, the CAL trap
" handler ("nest"), the dictionary search routine ("find"), the pop half
" of the stack push/pop convention, and EXIT. This is not a running
" Forth yet -- there is no text interpreter, no ":"/";" compiler, and no
" primitive set beyond the two needed to exercise the mechanics. It is a
" cold-start smoke test that hand-builds a 3-entry test dictionary (two
" primitives, BYE and EXIT, and a colon word GO that calls both in
" sequence) and drives NEXT/nest/find/EXIT far enough to prove a full
" call-and-return cycle assembles and executes as designed.
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

" --- header tag field values (this kernel's choice; see DESIGN.md notes) ---
" These sit only in header-word arithmetic below, never as an instruction
" operand, so plain assembler variables (not data cells) are correct here.
tag.colon=	0
tag.prim=	001000

" --- test dictionary ---
" BYE: a primitive that pushes a marker value rather than just leaving
" it in AC. Per DESIGN.md's Threading consequences, "TOS is not cached
" in AC" -- a primitive's result must be pushed to survive the next
" primitive call, so this is the well-formed shape, not the halt-and-
" inspect-AC shortcut the first cut used.
cnt.bye=	060000		" count=3

" EXIT: also an ordinary primitive (see DESIGN.md's Implementation
" notes on the 4 spare tags) -- a colon word calls it to return, same
" mechanism as calling BYE.
cnt.ex=		0100000		" count=4 ("EXIT"; only "EXI" is stored)

latest:	h.go		" head of the (3-entry) test dictionary

h.bye:	cnt.bye tag.prim 0		" link=0: BYE is the oldest entry
	0427145				" 'BYE' packed as sixbit
bye.body:
	lac byemark
	dac i 012	" push the result -- don't just leave it in AC
	jmp next
byemark:
	0123456

h.ex:	cnt.ex tag.prim h.ex-h.bye-1
	0457051				" 'EXI' packed as sixbit
ex.body:
	jms pop.rp	" AC := the caller's CAL-cell address, pushed by nest
	dac 010		" IP := that address directly -- no "tad m1" here,
			" unlike nest: EXIT resumes the cell *after* the
			" call, nest enters the callee's body
	jmp next

cnt.go=	040000			" count=2

h.go:	cnt.go tag.colon h.go-h.ex-1
	0475700			" 'GO ' packed as sixbit, space-padded
go.body:
	jmp bye.body		" cell 1: call BYE
	jmp ex.body		" cell 2: call EXIT -- return to our caller

" --- cold start test 1: drive NEXT/nest through a CAL cell, and back ---
" Simulates what a caller's compiled thread would contain when it
" references GO: a bare-address cell (CAL's opcode is 0) pointing at
" GO's thread. Wired up here by hand since there is no compiler yet.
" GO calls BYE (pushes a marker) then EXIT (returns here), so this
" exercises the full call/return cycle, not just the call half.
cboot:	go.body
halt1:	hlt
bootip:	cboot-1

start:	lac bootip
	dac 010
	jmp next
" Expected result: halts at halt1 with the data stack's bottom slot
" (address "dstack", the first and only push here) holding 0123456
" (byemark). AC itself is not meaningful at the halt: EXIT's own pop
" overwrites whatever BYE left there before returning.

" --- cold start test 2: exercise find() directly ---
" The test runner deposits tcnt/tname, then starts here. Expected
" result: AC = the word's body address, or 777777 (-1) if not found.
ftest:	jms find
	hlt

.=0500
rstack:	.=.+010		" 8-word return stack

.=0510
dstack:	.=.+010		" 8-word data stack
