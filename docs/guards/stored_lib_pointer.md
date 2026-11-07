# StoredLibPointer

**Checks that raw pointers from lib funs are not silently stored in ivars/class vars/constants: the ownership contract is decided on the C side, and the field says nothing about it.**

## Why

`@ctx = LibEngine.create()` — whether that pointer is a borrow (C owns
it and may free/realloc it under our feet) or a transfer (we own it
and must free it ourselves) is a contract no type in Crystal
expresses. The AST cannot prove which one it is, so this is a
"requires attention" marker (style), not a bug verdict: storing the
raw value in a field is exactly the shape where a wrong assumption
becomes a delayed crash — a use-after-free or a leak surfacing far
from this line.

Safer alternatives:

```crystal
class Context
  def initialize
    @ctx = LibEngine.create # ownership is explicit below
  end

  def close
    LibEngine.destroy(@ctx) # release where it was acquired
    @ctx = Pointer(Void).null
  end
end
```

or hide the pointer behind a handle — an index into a Crystal-side
table, so the C side never holds a GC pointer at all.

## What is tracked

- Assignments of a lib-shim call's result (declared in the file) to an
  ivar, class var or constant: `@ctx = LibEngine.create`,
  `CTX = LibEngine.create`.

## What is skipped (no false positives)

- Allocator funs (`malloc`, `calloc`, `realloc`, `xmalloc`, `strdup` —
  extendable via config `allocators`): MemoryLeak already owns the
  alloc/free pairing concern for them.
- Files that define a `finalize` or `close` anywhere — the project
  manages C lifetimes explicitly (generous, file-granular).
- Non-lib receivers (`@ctx = Engine.create`).

## Examples

Good:

```crystal
class Context
  def initialize
    @ctx = LibEngine.create
  end

  def close
    LibEngine.destroy(@ctx)
  end
end
```

Bad:

```crystal
class Context
  def initialize
    @ctx = LibEngine.create # borrow or own? nobody will ever know
  end
end
```
