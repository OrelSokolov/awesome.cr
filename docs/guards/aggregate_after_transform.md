# AggregateAfterTransform

**Checks for `xs.map { … }.sum`, `.size` and `.empty?` — an intermediate Array built just to be aggregated away.**

## Why

`xs.map { |x| f(x) }.sum` maps the whole collection into a fresh
Array, then reduces it to a number — the Array is pure garbage.
`xs.sum { |x| f(x) }` feeds each element straight into the reduction:
one pass, no allocation. Same for `.size` and `.empty?` on a map —
the block never changes the element count, so asking the original
collection answers directly.

## Examples

Good:

```crystal
total = invoices.sum { |inv| inv.amount }
count = invoices.size
```

Bad:

```crystal
total = invoices.map { |inv| inv.amount }.sum
count = invoices.map { |inv| inv.amount }.size
#        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ intermediate Array
```

## Config

```yaml
guards:
  AggregateAfterTransform:
    enabled: true
```
