# ArrayConcatInLoop

**Checks for Array concatenation inside loops (`arr += [x]`) — the whole Array is copied on every iteration.**

## Why

`arr += [x]` is `arr = arr + [x]`: a fresh Array with every old
element copied in, thrown away again on the next pass — quadratic
total work for what is a single append. `arr << x` appends in place
(amortized O(1)). Same shape as StringConcatInLoop, one type over.

## Examples

Good:

```crystal
acc = [] of Int32
items.each do |item|
  acc << item        # append in place, no copy
end
```

Bad:

```crystal
acc = [] of Int32
items.each do |item|
  acc += [item]      # full copy of acc, every iteration
end
```

## What is skipped

- Concatenation outside a loop — a one-off copy is not a hot spot.
- Non-literal right-hand sides (`arr += other`) — the receiver type
  of `+` is not provable from syntax, and `<<` is not always the
  same operation.
- Loop detection matches `while`/`until` plus the common block
  iterators (`times`, `each`, `map`, ...); a rare iterator that is
  missed only means a false negative.

## Config

```yaml
guards:
  ArrayConcatInLoop:
    enabled: true
```
