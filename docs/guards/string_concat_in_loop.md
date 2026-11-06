# StringConcatInLoop

**Checks for string concatenation inside loops (`s += "…"`) — a fresh String allocated every iteration.**

## Why

clippy's `string_add_assign` flags the same pattern in Rust: `s += "…"`
inside a loop allocates a fresh String each iteration; the fix is
`String::with_capacity` + `push_str`. In Crystal the fix is to append
into an `IO::Memory` (or `String::Builder`) and materialize the String
once, after the loop.

## Examples

Good:

```crystal
io = IO::Memory.new
while line = reader.gets
  io << line          # appends in place, no realloc
end
text = io.to_s        # one String for the whole loop
```

Bad:

```crystal
text = ""
while line = reader.gets
  text += line        # fresh String allocation every iteration
end
```

## What is skipped

- Concatenation outside a loop.
- Non-string right-hand sides (`n += 1` stays untouched) — only
  string literals and interpolations are flagged.
- Loop detection matches `while`/`until` plus the common block
  iterators (`times`, `each`, `map`, ...); a rare iterator that is
  missed only means a false negative — the guard never fires outside
  a loop.

## Config

```yaml
guards:
  StringConcatInLoop:
    enabled: true
```
