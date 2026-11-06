# RaiseInLibCallback

**Checks that procs passed to lib-shim funs never raise: the exception would unwind through the library's C frames.**

## Why

`LibWatch.each(->(row : Int32) { raise "corrupt" })` hands a Crystal proc
to C. When the library calls back into it and the proc raises, the
exception has to unwind the C frames the library used to make the call —
the runtime cannot do that correctly. It is undefined behaviour; in
practice the process aborts with a wrecked stack, far from the bug.

The fix is to never let an exception cross the C boundary: signal the
error through the callback's return value, or catch it inside the
callback.

```crystal
lib LibWatch
  fun each(cb : Int32 -> Void) : Void
end

LibWatch.each(->(row : Int32) {
  raise "row is corrupt" # unwinds through LibWatch's C frames — UB
})
```

## What is tracked

- Proc literals passed directly as arguments of a lib-shim call
  (`LibFoo.fun(->(x) { ... })`), where the lib is declared in the file
  or follows the `Lib`-prefix naming convention (stdlib's `LibC`).
- Any `raise` or `reraise` anywhere in the proc's subtree — even
  nested in blocks, because it still unwinds through C when it fires.

## What is skipped (no false positives)

- Procs stored in a variable and passed later (`cb = ->{ ... };`
  `LibFoo.fun(cb)`) — only literals at the call site are tracked (a
  false negative by design).
- Procs passed to non-lib receivers (`Watch.each(->(x) { raise })`).
- Raises in plain defs — only callbacks actually invoked from C cross
  the boundary.

## Examples

Good:

```crystal
lib LibWatch
  fun each(cb : Int32 -> Int32) : Void
end

LibWatch.each(->(row : Int32) {
  row < 0 ? 1 : 0 # error signalled via the return value
})
```

Bad:

```crystal
lib LibWatch
  fun each(cb : Int32 -> Void) : Void
end

LibWatch.each(->(row : Int32) {
  raise "row is corrupt" # unwinds through LibWatch's C frames — UB
})
```
