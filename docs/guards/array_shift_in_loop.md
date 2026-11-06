# ArrayShiftInLoop

**Checks for `shift`/`unshift` on arrays inside loops — Array is the wrong queue, O(n) per call where Deque is O(1).**

## Why

Rust lore: `Vec::remove(0)` in a loop is O(n²); use a `VecDeque` with
O(1) pops at both ends. In Crystal `Array#shift`/`#unshift` likewise
move the whole buffer (memmove per call), while `Deque` is
ring-buffered with O(1) `shift`/`#unshift` — Crystal's VecDeque.

## Examples

Good:

```crystal
queue = Deque{first, second}
while item = queue.shift?   # O(1)
  process item
end
```

Bad:

```crystal
queue = [first, second]
while item = queue.shift?   # O(n) memmove per call
  process item
end
```

## What is skipped

- Calls outside a loop — one shift is not a hot spot.
- Advisory by nature: any receiver works for `shift`, not just Array
  (`Hash#shift` is O(1)), so if the receiver is not an Array, ignore
  the finding.

## Config

```yaml
guards:
  ArrayShiftInLoop:
    enabled: true
```
