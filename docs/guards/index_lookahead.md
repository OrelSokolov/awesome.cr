# IndexLookahead

**Checks for `xs.size.times { |i| xs[i + 1] }` — lookahead indexing past the loop's last element.**

## Why

Neighbor access (compare/swap with the next element) is the pattern,
and the bug is always the same: the loop is bounded by `xs.size` —
the last `i` is `xs.size - 1` — while the body reads `xs[i + k]` with
`k ≥ 1`, which hits index `xs.size` exactly when the loop is at its
final pass.

## Examples

Good:

```crystal
items.each_with_index do |item, i|
  process items[i + 1] if i + 1 < items.size
end
```

Bad:

```crystal
items.size.times do |i|
  process items[i + 1]   # IndexError on the last iteration
end
```

## What is skipped

- Any body comparing the loop variable (`if i + 1 < xs.size`,
  `next if i == xs.size - 1`) — the author is already guarding the
  boundary; a false negative beats a false positive.
- An adjusted range end (`0...xs.size - 1`) — the safe form of
  neighbor-pair iteration.
- `i - 1`, bare `i`, and indexing a collection other than the one
  bounding the loop.

## Config

```yaml
guards:
  IndexLookahead:
    enabled: true
```
