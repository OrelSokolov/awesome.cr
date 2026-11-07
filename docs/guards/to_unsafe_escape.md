# ToUnsafeEscape

**Checks that `to_unsafe` pointers don't outlive their call: the GC does not scan C memory, so a stored pointer keeps nothing alive.**

## Why

`String#to_unsafe` / `Slice#to_unsafe` return a raw pointer into the
object's bytes — memory that lives in the Boehm-GC heap. The pointer is
valid for the duration of the C call it was passed to, but it is not a
loan the Crystal side can forget: the backing object is collectable
the moment nothing on the Crystal side references it. An ivar holding
just the pointer keeps nothing alive, so

```crystal
class Decoder
  def initialize(@blob : Slice(UInt8))
    @raw = @blob.to_unsafe # keeps the pointer, not the slice — one GC
  end                     # cycle later @raw dangles
end
```

crashes much later, in C code reading a buffer that no longer exists.
The same holds after a buffer grows — `push` reallocates and the old
pointer is garbage even without the GC.

The fix is either to keep the owner alive next to the pointer, or to
copy the bytes into C-owned memory and manage that lifetime explicitly
(malloc + free — see MemoryLeak/DoubleFree):

```crystal
def initialize(@blob : Slice(UInt8))
  @raw = @blob.to_unsafe  # pointer...
  @keep = @blob           # ...and its owner, alive as long as @raw
end
```

## What is tracked

- An assignment whose value **is** the `to_unsafe` call:
  `@raw = x.to_unsafe`, `@@raw = ...`, `HEADER = ...`.
- An explicit `return x.to_unsafe`.

## What is skipped (no false positives)

- Pointers passed straight into a lib call
  (`LibFoo.draw(x.to_unsafe, x.size)`) — the intended use.
- Receivers that are stored alive somewhere in the file
  (`@keep = @blob` next to `@raw = @blob.to_unsafe`) — the owner is
  reachable for as long as the keeper field lives.
- Assignments of other calls (`@copy = data.dup`), and wrapping shapes
  (`x.to_unsafe.as(Int8*)`, pointer arithmetic) — false negatives by
  design.

## Examples

Good:

```crystal
class Decoder
  def initialize(@blob : Slice(UInt8))
    @raw = @blob.to_unsafe  # pointer...
    @keep = @blob           # ...and its owner, alive as long as @raw
  end
end
```

Bad:

```crystal
class Decoder
  def initialize(@blob : Slice(UInt8))
    @raw = @blob.to_unsafe # ivar keeps the pointer, not the slice
  end

  def raw_ptr
    return @blob.to_unsafe # the caller outlives @blob's next GC
  end
end
```
