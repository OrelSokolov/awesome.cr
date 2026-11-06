# UncheckedLibPointer

**Checks that pointers returned by lib-shim funs are null-checked before `.value`.**

## Why

A C fun returning `T*` maps to `Pointer(T)` in Crystal, and C happily
returns NULL from them ("not found", "out of range", "error"). The
Crystal type says nothing about that, so `.value` on a NULL pointer is
a segfault.

```crystal
lib LibGeo
  fun find(id : Int32) : Float64*
end

def fetch(id)
  point = LibGeo.find(id)
  point.value # no null check in between — segfault when NULL
end
```

## What is tracked

- The **chained** shape `LibGeo.find(id).value` — flagged wherever it
  appears, in any scope.
- The **stored** shape `point = LibGeo.find(id)` … `point.value`,
  paired within one statement block (like DoubleFree): an assignment
  from a pointer-returning lib fun starts tracking, and a `.value` on
  the unchanged local/ivar is flagged.
- A lib declared in the file is checked precisely: only funs declared
  to return `T*` / `Pointer(T)` count. Lib-prefixed shims bound
  elsewhere (stdlib's `LibC`) can't be verified, so any of their funs
  is assumed to return a pointer — `.value` on the result of anything
  else (numbers, structs) wouldn't compile anyway.

## What is skipped (no false positives)

- Any guard between assignment and deref: the variable appearing in an
  `if`/`unless`/`while`/`until` condition (`if point`, including
  `if point = LibGeo.find(id)` at the source), or a `.nil?` / `.null?`
  check.
- Any reassignment of the variable in between — nested in blocks too.
  A reassignment from the same lib fun starts tracking again.
- Derefs in sibling `if`/`else` branches — each branch is its own
  statement block.
- Same-named variables in nested scopes (a def inside a def's block)
  — new scopes are not descended into.
- Non-lib receivers (`repo.find(id).value`).

## Examples

Good:

```crystal
lib LibGeo
  fun find(id : Int32) : Float64*
end

def fetch(id)
  if point = LibGeo.find(id) # NULL-checked right at the source
    point.value
  end
end
```

Bad:

```crystal
lib LibGeo
  fun find(id : Int32) : Float64*
end

def fetch(id)
  point = LibGeo.find(id)
  point.value # no null check in between — segfault when NULL
end
```
