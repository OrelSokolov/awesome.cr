# ToSWithoutIo

**Checks for `def to_s` without arguments — an override that `io <<`, interpolation and `puts` never call.**

## Why

`io << obj`, string interpolation and `puts obj` all funnel through
`to_s(io : IO)` — the zero-arg `Object#to_s` is just a wrapper that
calls `to_s(io)` and materializes a String. Overriding the wrapper
changes neither the IO path nor interpolation: every caller keeps the
default representation, and whoever calls `obj.to_s` directly pays
for a fresh String. Define `def to_s(io : IO)` and write into the io
instead.

## Examples

Good:

```crystal
def to_s(io : IO)
  io << @name << '#' << @id   # feeds io <<, interpolation, puts
end
```

Bad:

```crystal
def to_s
  "#{@name} #{@id}"   # io << obj still prints the default
end
```

## What is skipped

- Nothing provable — a zero-arg `to_s` (with or without a return
  type, abstract included) is always the wrong hook. If the zero-arg
  form is deliberate API in your codebase, switch the whole pattern
  off with `check_to_s: false`.

## Config

```yaml
guards:
  ToSWithoutIo:
    enabled: true
    check_to_s: true   # separately disableable (a style dispute)
```
