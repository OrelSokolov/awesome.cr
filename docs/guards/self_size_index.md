# SelfSizeIndex

**Checks for indexing a collection by its own size: `xs[xs.size]` — always out of bounds.**

## Why

The classic off-by-one. For every stdlib container the last valid
index is `size - 1`, so `xs[xs.size]` raises the moment it runs
(Array/String: IndexError, Hash: KeyError). No receiver makes the
pattern legal, which is what makes it provable syntactically.

## Examples

Good:

```crystal
last = items[items.size - 1]
first_empty = items[items.size]? # deliberate nil-on-miss
```

Bad:

```crystal
last = items[items.size] # one past the end — IndexError

n = rows.size
tail = rows[n]           # same bug through an alias
```

## What is skipped

- The nilable `xs[xs.size]?` form — that is the deliberate
  nil-on-miss check, not a crash.
- An alias whose variable was reassigned between `n = xs.size` and
  the access — the index is no longer provably the size.
- Indexing by another collection's size (`items[others.size]`) —
  nothing proves the two collections share a length.

## Config

```yaml
guards:
  SelfSizeIndex:
    enabled: true
```
