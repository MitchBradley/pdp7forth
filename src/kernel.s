" PDP-7 Forth -- kernel skeleton
"
" First assembling cut at the pieces DESIGN.md already settles: NEXT, the
" CAL trap handler ("nest"), and the dictionary search routine ("find").
" This is not a running Forth yet -- there is no text interpreter, no
" ":"/";" compiler, and no primitive set. It is a cold-start smoke test
" that hand-builds two dictionary entries (a primitive "BYE" and a colon
" word "GO" that calls it) and drives NEXT/nest/find far enough to prove
" the threading and search mechanics from DESIGN.md actually assemble and
" execute as described.
"
" Assemble with (from the pdp7forth repo root):
"   tools/pdp7-unix/tools/as7 -f list -o build/kernel.lst \
"       tools/pdp7-unix/src/sys/sop.s src/kernel.s
"
" Two judgement calls were needed that DESIGN.md leaves unspecified; both
" are flagged in DESIGN.md's "Implementation notes" section for
" confirmation rather than silently promoted to [decided]:
"   - Header tag numbering (colon=0, primitive=1, constant=2, variable=3,
"     4-7 spare), matching the table's row order.
"   - Name characters packed as classic SIXBIT (ascii - 040), matching
"     "6-bit characters" plus case-folded input.
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
" BYE: a primitive. Its header's body (word 2) is straight-line machine
" code -- here just enough to prove control got there, no NEXT/jmp next,
" since nothing calls back into it.
cnt.bye=	060000		" count=3, positioned into the count field

latest:	h.go		" head of the (2-entry) test dictionary

h.bye:	cnt.bye tag.prim 0	" link=0: BYE is the oldest entry
	0427145			" 'BYE' packed as sixbit (ascii-040)
bye.body:
	lac byemark
	hlt
byemark:
	0123456

cnt.go=	040000			" count=2

h.go:	cnt.go tag.colon h.go-h.bye-1
	0475700			" 'GO ' packed as sixbit, space-padded
go.body:
	jmp bye.body		" GO's one-cell thread: call BYE

" --- cold start test 1: drive NEXT/nest through a CAL cell ---
" Simulates what a caller's compiled thread would contain when it
" references GO: a bare-address cell (CAL's opcode is 0) pointing at
" GO's thread. Wired up here by hand since there is no compiler yet.
cboot:	go.body
bootip:	cboot-1

start:	lac bootip
	dac 010
	jmp next
" Expected result: bye.body runs, AC = 0123456 (byemark), then halts.

" --- cold start test 2: exercise find() directly ---
" Looks up "GO" starting from latest and returns its body address in AC.
cnt2:	040000
name2:	0475700

test2:	lac cnt2
	dac tcnt
	lac name2
	dac tname
	jms find
	hlt
" Expected result: AC = go.body's address (found), or -1 if the search
" logic is wrong.

.=0500
rstack:	.=.+010		" 8-word return stack

.=0510
dstack:	.=.+010		" 8-word data stack
