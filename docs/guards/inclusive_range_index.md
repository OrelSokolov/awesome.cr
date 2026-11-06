# InclusiveRangeIndex

**Checks for `(0..xs.size).each { |i| xs[i] }` — the last iteration indexes one past the end.**

## Why

The inclusive `..` range runs its last iteration with
`i == xs.size`, and `xs[i]` raises IndexError right there. The `...`
and `times` forms stop at `xs.size - 1` and are safe — the bug hides
in a single extra dot.

## Examples

Good:

```crystal
(0...items.size).each do |i|
  process items[i]
end
```

Bad:

```crystal
(0..items.size).each do |i|
  process items[i]   # i == items.size on the last pass
end
```

## What is skipped

- Exclusive ranges (`0...xs.size`), `xs.size.times`, adjusted ends
  (`0..xs.size - 1`) — all safe bounds.
- Offsets on the index (`xs[i - 1]`) — the guard judges only the
  bare loop variable.
- Indexing a collection other than the one bounding the loop —
  nothing proves they share a length.

## Config

```yaml
guards:
  InclusiveRangeIndex:
    enabled: true
```
