# PDP-7 Forth — Design Notes

Goal: a rudimentary but running Forth that fits in the 8K 18-bit words of a PDP-7.

Status markers: **[decided]** = settled by Mitch; **[proposed]** = worked out in discussion, not yet confirmed; **[open]** = unresolved.

## Machine facts driving the design

- 18-bit words, 8K core; memory-reference instructions are 4-bit opcode + 1 indirect bit + 13-bit address.
- Auto-index registers at 10–17 (octal) pre-increment when used indirectly.
- Single accumulator (AC) plus Link; MQ only with EAE (EAE availability **[open]**).
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

## Open issues

- **[open]** EXECUTE with colon words. Nest reads the cell through `C(10)`, so EXECUTE can't simply XCT a colon token. Proposal: the xt is the header address p. EXECUTE builds the cell in a scratch location followed by an EXIT cell, pushes IP, and points IP at the scratch cell. That works for every tag.
- **[open]** Uses for the 4 spare tags.
- **[open]** Stack directions and pop sequences. Auto-index registers only pre-increment, so one of push/pop is manual for each stack.
- **[open]** Whether EAE is assumed.
- **[open]** Target I/O: console teletype, paper tape.

## Idea stack (deferred)

- Token threading with two 9-bit tokens per word: roughly halves thread size, at the cost of a table lookup in NEXT and a 512-token limit.
- Aligning headers on 2-word boundaries so the link's low bit is always zero and can serve as a flag. Superseded for now by the 512-word span, which already bought the needed bits.
- Separating heads from bodies so headers can be discarded in a turnkey image.
- A zero-count dummy header (it never matches) to bridge gaps over 512 words, if the ALLOT limit becomes a problem.
