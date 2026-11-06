# UnusedIndex

**Checks for `each_with_index` blocks whose index parameter is never used.**

## Why

clippy's `unused_enumerate_index`: iterating with an index you never
use makes readers look for a reason that isn't there, and in Crystal
`each` also skips the index bookkeeping entirely. If the block's
second parameter (the index) is never referenced in the body, plain
`each` does the same job.

## Examples

Good:

```crystal
items.each do |item|
  process item
end
```

Bad:

```crystal
items.each_with_index do |item, i|
  process item     # i never used
end
```

## What is skipped

- An index named `_` (or `_something`) is treated as intentionally
  unused and not flagged — that's already idiomatic.

## Config

```yaml
guards:
  UnusedIndex:
    enabled: true
```
