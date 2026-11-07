# PointerOfEscape

**Checks that `pointerof(x)` doesn't reach a storing lib fun or a field: the address is only as alive as its GC-managed owner.**

## Why

`LibStats.register_counter(pointerof(@count))` gives C the address of
an ivar. Boehm doesn't move objects, so the address itself stays
valid — but the *object holding the ivar* is GC-managed, and the
collector does not scan C memory: once the instance is unreachable on
the Crystal side, the next tick of C's counter writes through a
dangling pointer. The AST cannot prove the owner outlives C's use, so
this is a "requires attention" marker (style), not a bug verdict. The
same applies to a field keeping `pointerof(x)`: the field pins the
address, not the owner.

Safer alternatives: pass a value C copies (register the number, not
the address); or hand C a Box (see UnpinnedLibCallback for keeping it
alive); or allocate the C-side memory with malloc and own it
explicitly (then MemoryLeak's pairing applies).

## What is tracked

- `pointerof(...)` passed as an argument to a storing lib fun — fun
  names that say the library keeps the argument (`set_*`,
  `register_*`, `on_*`, `add_*`, `attach_*`, `subscribe_*` prefixes,
  or callback/handler/listener/hook in the name; more via config
  `storage_funs`, and storing-looking names that actually don't store
  can be exempted via `ignore_funs`).
- `@field = pointerof(x)` / `CONST = pointerof(x)` — the address
  escaping into a field.

## What is skipped (no false positives)

- `pointerof` passed to fire-and-forget funs (`LibMem.fill(ptr, n)`)
  — the address only needs to live for the duration of the call.
- Non-lib receivers (`Stats.register_counter(pointerof(@count))`).

## Examples

Good:

```crystal
lib LibStats
  fun register_counter(value : Int32) : Void # C copies the number
end

LibStats.register_counter(@count)
```

Bad:

```crystal
LibStats.register_counter(pointerof(@count)) # C keeps the address
                                             # of a GC-managed ivar
```
