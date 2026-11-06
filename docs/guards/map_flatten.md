# MapFlatten

**Checks for `xs.map { … }.flatten` — an intermediate Array allocated just to be thrown away.**

## Why

clippy's `map_flatten`: `iter.map(f).flatten()` should be
`iter.flat_map(f)`. Crystal is the same — `map { … }.flatten` walks
the collection twice and allocates the intermediate Array just to
discard it, while `flat_map` yields the block's results one by one
straight into the output Array: one pass, no intermediate allocation.

## Examples

Good:

```crystal
words = lines.flat_map(&.split)   # one pass
```

Bad:

```crystal
words = lines.map(&.split).flatten
#            ^^^^^^^^^^^ intermediate Array
#                        allocated, then dropped
```

## Config

```yaml
guards:
  MapFlatten:
    enabled: true
```
