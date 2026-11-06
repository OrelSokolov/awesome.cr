# SelectFirst

**Checks for `xs.select { … }.first` — the whole filtered Array built to take one element.**

## Why

`xs.select { |x| ok?(x) }.first` runs the predicate over every
element and allocates the full result Array, then keeps a single
value. `xs.find { |x| ok?(x) }` stops at the first match — the
predicate runs only as far as needed and nothing is allocated
(`find?` is the nilable twin of `first?`).

## Examples

Good:

```crystal
first_bad = results.find { |r| r.error? }
```

Bad:

```crystal
first_bad = results.select { |r| r.error? }.first
#           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ every element filtered,
#           an Array allocated, one value kept
```

## Config

```yaml
guards:
  SelectFirst:
    enabled: true
```
