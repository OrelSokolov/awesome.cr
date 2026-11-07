# RaiseInFunDef

**Checks that `fun` defs never let an exception escape: it would unwind into whatever C code called the fun.**

## Why

A top-level `fun vib_push(h : Int64) : Int64 ... end` is an ABI entry
point: a plain C host (dlopen, a C library, another language's
runtime) calls it directly. When Crystal code inside the fun raises,
the exception must unwind the caller's foreign frames — the runtime
cannot do that correctly; it is undefined behaviour, in practice an
abort or a wrecked stack inside the host, far from the raise that
caused it. This is the `fun`-def half of RaiseInLibCallback (which
covers procs C calls back into): every exception crossing the C
boundary in either direction is UB.

The fix is the same discipline a C API uses — catch inside, return an
error code:

```crystal
fun vib_push(h : Int64) : Int64
  State.push(h)
  0
rescue
  -1 # the host sees the error, the boundary stays intact
end
```

## What is tracked

- Any `raise`/`reraise` in a `fun` body that is not inside a
  `begin/rescue` (or fun-level `rescue`) of that body — a caught raise
  never crosses the boundary.
- Raises nested in blocks or proc literals within the fun are flagged
  too: they unwind through the fun either way.

## What is skipped (no false positives)

- Raises inside an exception handler in the fun body (including a
  `reraise` in a rescue clause — a false negative by design).
- Raises in plain defs — only `fun` defs are C entry points.
- `fun x = ...` declarations inside a `lib` (they have no body).

## Examples

Good:

```crystal
fun vib_push(h : Int64) : Int64
  State.push(h)
  0
rescue
  -1 # error signalled via the return value
end
```

Bad:

```crystal
fun vib_push(h : Int64) : Int64
  raise "bad handle" # unwinds into the C host — undefined behaviour
end
```
