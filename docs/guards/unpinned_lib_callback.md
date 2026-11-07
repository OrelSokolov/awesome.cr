# UnpinnedLibCallback

**Checks that closures passed to storing lib-shim funs are kept alive: the GC can free an unreferenced closure the library still holds.**

## Why

`LibUi.on_click(->(button : Int32) { ... })` passes a Crystal proc into
C. The proc's code and captured environment live in the Boehm-GC heap,
and an inline literal has no reference once the call returns — only
the (conservatively scanned) stack keeps it alive during the call
itself. If the library *stores* the callback and invokes it later, the
collector may have freed the closure by then: the next callback from C
dereferences a dead object and crashes, typically long after the
registration, far from the bug.

The fix is to keep the closure alive for as long as C holds it:

```crystal
lib LibUi
  fun on_click(cb : Int32 -> Void) : Void
end

# A constant holds the closure alive for the whole program —
# exactly as long as LibUi keeps the callback.
ON_CLICK = ->(button : Int32) { Counter.add(button) }

LibUi.on_click(ON_CLICK)
```

`Box.box(x)` passed inline has the same problem — the box is
GC-managed like the proc; keep it in a constant or class variable too.

## What is tracked

- Proc literals (`->(x) { ... }`) and `Box.box(...)` / `Box.new(...)`
  passed **directly as arguments** of a lib-shim call
  (`LibFoo.set_callback(->(x) { ... })`), where the lib is declared in
  the file or follows the `Lib`-prefix naming convention (stdlib's
  `LibC`).
- Only fun names that say the library keeps the callback:
  `set_`/`register_`/`on_`/`add_`/`attach_`/`subscribe_` prefixes, or
  `callback`/`handler`/`listener`/`hook` in the name. More names can
  be added via config:

  ```yaml
  UnpinnedLibCallback:
    storage_funs: [run_with]
    ignore_funs: [on_init]
  ```

## What is skipped (no false positives)

- Fire-and-forget shims (`LibC.qsort(...)`, `LibFoo.each(...)`): the
  closure is stack-reachable for the whole call there.
- Procs stored in a variable and passed later — the variable keeps the
  closure alive (only literals at the call site are tracked).
- Procs passed to non-lib receivers (`Ui.on_click(->(x) { ... })`).

## Examples

Good:

```crystal
ON_CLICK = ->(button : Int32) { Counter.add(button) }
LibUi.on_click(ON_CLICK)
```

Bad:

```crystal
LibUi.on_click(->(button : Int32) { # inline literal: unreferenced
  Counter.add(button)              # once the GC runs — crash
})
```
