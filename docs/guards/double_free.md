# DoubleFree

**Checks that the same pointer is not passed to a lib-shim deallocator twice without a reassignment in between.**

## Why

`LibFoo.free(ptr)` releases C heap memory that the Crystal GC will
never manage. Passing the same pointer to a C deallocator twice is a
double free — undefined behaviour that corrupts the C heap and tends
to surface as crashes far away from the bug.

```crystal
lib LibGeo
  fun malloc(size : Int32) : Void*
  fun realloc(ptr : Void*, size : Int32) : Void*
  fun free(ptr : Void*)
end

def close(ptr)
  LibGeo.free(ptr)
  cleanup
  LibGeo.free(ptr) # no reassignment in between — double free
end
```

The rule: within one statement block, a second `LibFoo.free(ptr)` on a
variable with no assignment to that variable between the two calls is
always a bug. `ptr = LibFoo.malloc(...)` or
`ptr = LibFoo.realloc(ptr, ...)` between the calls is the only thing
that makes the second free legal.

## What is tracked

- Statement-level `LibFoo.free(x)` / `LibFoo.xfree(x)` calls where
  `LibFoo` is a `lib` declared in the file, or (for libs bound
  elsewhere, like stdlib's `LibC`) follows the `Lib`-prefix naming
  convention.
- The freed argument must be a local variable or an instance variable
  (`ptr`, `@handle`) — anything else (field access, call results)
  can't be tracked syntactically and is skipped.
- Deallocator fun names (defaults): `free`, `xfree`.

## What is skipped (no false positives)

- Frees in sibling `if`/`else` branches — each branch is its own
  statement block, only one executes.
- `free(ptr) if cond` — the modifier wraps the call in an `If`, so it
  is not paired (a deliberate false negative).
- Any assignment to the variable anywhere between the two calls —
  including `ptr = ...` nested inside blocks or larger expressions.
- Non-lib receivers (`Foo.free(ptr)`, `ptr.free`).

## Examples

Good:

```crystal
lib LibGeo
  fun malloc(size : Int32) : Void*
  fun realloc(ptr : Void*, size : Int32) : Void*
  fun free(ptr : Void*)
end

def grow(ptr)
  ptr = LibGeo.realloc(ptr, 128) # fresh pointer...
  LibGeo.free(ptr)               # ...so this is the first free
end
```

Bad:

```crystal
lib LibGeo
  fun malloc(size : Int32) : Void*
  fun free(ptr : Void*)
end

def close(ptr)
  LibGeo.free(ptr)
  cleanup
  LibGeo.free(ptr) # no reassignment in between — double free
end
```

## Config

```yaml
guards:
  DoubleFree:
    enabled: true
    deallocators: [free, xfree]
```
