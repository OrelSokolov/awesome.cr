# MapCompact

**Checks for `xs.map { … }.compact` — two passes and an intermediate Array where one call would do.**

## Why

`xs.map { |x| f(x) }.compact` maps into a fresh Array, then walks it
again to copy the non-nil values into another one. `xs.compact_map {
|x| f(x) }` appends each non-nil result straight into the output
Array: one pass, one allocation. Companion to MapFlatten.

## Examples

Good:

```crystal
names = users.compact_map { |u| u.email }
```

Bad:

```crystal
names = users.map { |u| u.email }.compact
#            ^^^^^^^^^^^^^^^^^^^ intermediate Array,
#                                 walked again by compact
```

## Config

```yaml
guards:
  MapCompact:
    enabled: true
```
