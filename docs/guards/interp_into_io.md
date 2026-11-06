# InterpIntoIo

**Checks for string interpolation inside IO calls — `io << "a#{b}c"` allocates the full String before writing.**

## Why

`io << "a#{b}c"` expands to `io << String.interpolation("a", b, "c")`:
the interpolated String is fully allocated before the `<<` even runs
(verified on Crystal 1.21 — literal_expander.cr). Appending the parts
separately (`io << "a" << b << "c"`) lets each `to_s(io)` write
directly into the IO: zero intermediate Strings.

## Examples

Good:

```crystal
io << "user=" << user.name << " id=" << user.id
# each to_s(io) writes into io directly
```

Bad:

```crystal
io << "user=#{user.name} id=#{user.id}"
# String.interpolation allocates the full String first
```

## What is skipped

- For `<<` the guard fires only on IO-ish receiver names (`io`,
  `stdout`, `..._io`, ...) — on an unknown receiver (an Array, say)
  the append-the-parts fix would not apply, and a false negative
  beats a false positive.
- `puts`/`print` (and `io.puts`/`io.print`) have IO semantics by
  definition, so they always fire.

## Config

```yaml
guards:
  InterpIntoIo:
    enabled: true
```
