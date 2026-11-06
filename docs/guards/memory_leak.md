# MemoryLeak

**Checks that C heap allocations from lib shims are paired with a matching free somewhere in the file.**

## Why

`lib LibFoo ... fun malloc(...)` binds raw C allocators into Crystal.
The memory they return lives on the C heap — the Crystal GC will never
release it. The only correct lifecycle is the C one: every allocation
is eventually passed to a deallocator.

```crystal
lib LibGeo
  fun malloc(size : Int32) : Void*
  fun free(ptr : Void*)
end

class Polygon
  def initialize
    @points = LibGeo.malloc(64) # C heap, invisible to the GC
  end

  def finalize
    LibGeo.free(@points)        # the only way to release it
  end
end
```

The base check (v1): a file that calls an allocator fun must also call
a deallocator fun of the same lib at least once. Zero `free` calls
anywhere in the file means the allocation can never be released — a
certain leak, not a style nit. One free covering several allocations
passes; that is the deliberately minimal, zero-false-positive first
step.

## What is tracked

- Calls of the form `LibFoo.malloc(...)` where `LibFoo` is a `lib`
  declared in the file — the shim itself (`fun malloc`) is seen in the
  compiler's AST, so **no C parsing is required**.
- Allocators by fun name (defaults): `malloc`, `calloc`, `realloc`,
  `xmalloc`, `strdup`. Deallocators: `free`, `xfree`.
- Libs bound elsewhere but called in the file (e.g. stdlib's
  `LibC.malloc`) — tracked via the `Lib`-prefix naming convention.
- Pairing is per-lib: `LibA.free` does not excuse `LibB.malloc`.

## What is skipped

- Non-lib receivers (`Foo.malloc`, `Pointer.malloc`) — never flagged.
- Calls to non-allocator funs of a lib (`LibGeo.sample_rate`).
- Calls inside fun bodies (`fun x = ... end` defines a shim, it does
  not use one).

## Examples

Good:

```crystal
lib LibGeo
  fun malloc(size : Int32) : Void*
  fun free(ptr : Void*)
end

class Polygon
  def initialize
    @points = LibGeo.malloc(64)
  end

  def finalize
    LibGeo.free(@points) # paired with the malloc above
  end
end
```

Bad:

```crystal
lib LibGeo
  fun malloc(size : Int32) : Void*
  fun free(ptr : Void*)
end

class Polygon
  def initialize
    @points = LibGeo.malloc(64) # LibGeo.free is never called — leak
  end
end
```

## Config

```yaml
guards:
  MemoryLeak:
    enabled: true
    # fun names treated as C allocators / deallocators (exact match):
    allocators: [malloc, calloc, realloc, xmalloc, strdup]
    deallocators: [free, xfree]
```

Custom shims with unusual names (e.g. `my_alloc` / `my_release`) are
covered by overriding these lists.

## Limitations (v1)

- The check is per-file: a malloc in one file and its free in another
  passes. Cross-file pairing needs a project-wide pass (see ROADMAP).
- "At least one free" proves the deallocator is reachable, not that
  every allocation is freed on every path — per-call pairing is a
  follow-up.
