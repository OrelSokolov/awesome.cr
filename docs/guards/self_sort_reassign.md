# SelfSortReassign

**Checks for reassignments like `xs = xs.sort` — paying for a copy nobody needs.**

## Why

clippy's `redundant_clone` family: reassigning a collection to the
result of its own non-mutating method throws away the original and
keeps a fresh copy. The bang versions (`sort!`, `uniq!`, ...) do the
same job in place with no allocation — the Crystal take on Rust's
`vec.sort()` / `sort_unstable()`.

## Examples

Good:

```crystal
items.sort!           # in place, no copy
items.sort! { |a, b| a.qty <=> b.qty }
```

Bad:

```crystal
items = items.sort    # allocates a sorted copy,
                      # then drops the original
```

## What is skipped

- Advisory by nature: the bang version mutates the original object,
  so it is only safe when nothing else holds a reference to it —
  the message says so.
- Comparator blocks are fine — `sort! { … }` exists too.

## Config

```yaml
guards:
  SelfSortReassign:
    enabled: true
```
