# TimesIndex

**Checks for `xs.size.times { |i| … xs[i] … }` — index machinery nobody needs.**

## Why

The idiom re-derives every element through a bounds-checked `[]`
and drags an index variable through the block, when `xs.each { |x|
… }` hands over the element itself — no Integer object, no bounds
check.

## Examples

Good:

```crystal
items.each do |item|
  process item
end
```

Bad:

```crystal
items.size.times do |i|
  process items[i]   # bounds check + index bookkeeping per element
end
```

## What is skipped

- Blocks that use the index for anything other than indexing the very
  same receiver — the guard fires only when `xs[i]` appears and `i`
  is the block argument; anything richer is left alone.

## Config

```yaml
guards:
  TimesIndex:
    enabled: true
```
