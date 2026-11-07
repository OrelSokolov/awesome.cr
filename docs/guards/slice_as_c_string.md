# SliceAsCString

**Checks that `x.to_unsafe` passed to a C-string parameter of a lib fun travels with a length: a Slice receiver means C reads past the buffer end.**

## Why

`LibCfg.read(buf.to_unsafe)` hands C a raw buffer pointer. If the
receiver is a String, the bytes are NUL-terminated and C reading them
as a string is fine; if it is a Slice (or StaticArray), they are
NOT — C's strlen/read runs past the buffer end, which is undefined
behaviour: usually garbage, occasionally a segfault, always far from
the call. The AST cannot tell String from Slice at the receiver, so
this is a "requires attention" marker (style), not a bug verdict.

Safer alternatives:

```crystal
lib LibCfg
  fun read_n(data : UInt8*, len : Int32) : Int32
end

LibCfg.read_n(buf.to_unsafe, buf.size)  # pointer and its length
LibCfg.read_n(String.new(buf).to_unsafe, buf.size) # terminated copy
```

or bind the fun as taking `(data : UInt8*, len : Int32)` in the first
place.

## What is tracked

- `.to_unsafe` passed to a `UInt8*`/`Int8*`/`Char*` parameter of a lib
  fun **declared in the file**, when no argument of the call carries a
  length (`size`, `bytesize`, `length`, `len`, `count`, `cap` —
  extendable via config):

  ```yaml
  SliceAsCString:
    length_names: [num_items]
  ```

## What is skipped (no false positives)

- Calls with any length-named argument (`read(buf.to_unsafe, n)`).
- String literal receivers (`"default.cfg".to_unsafe`) — NUL-terminated
  by construction.
- Parameters that are not C strings (`Float64*`, `Void*`, …).
- Libs not declared in the file (unknown signature — a false negative
  by design).

## Examples

Good:

```crystal
LibCfg.read_n(buf.to_unsafe, buf.size) # pointer and its length
```

Bad:

```crystal
LibCfg.read(buf.to_unsafe) # buf may be a Slice — no NUL, no length
```
