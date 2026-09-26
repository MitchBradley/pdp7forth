# PDP-7 Forth

A rudimentary Forth for a retro PDP-7 that must fit in 8K 18-bit words. See `DESIGN.md` for the full design. Read it before proposing changes, and update it when decisions are made.

Ground rules:
- Memory is the governing constraint. Prefer space savings over speed unless told otherwise.
- Single vocabulary, no smudge bit, no DOES>.
- Headers are 2 words: `[count:5][imm:1][tag:3][link:9]`, then three 6-bit characters. The link is relative (distance − 1), with a 512-word span.
- Thread cells carry the tag in the opcode bits and are executed directly by `xct i 10` (IP in auto-index 10).
- Keep the **[decided]** / **[proposed]** / **[open]** markers in DESIGN.md accurate. Don't promote a proposal to decided without confirmation.

The user is the inventor of Open Firmware and a past chair of the ANSI Forth technical subcommittee. Skip Forth basics.
