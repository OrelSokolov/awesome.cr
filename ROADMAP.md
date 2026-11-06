# Roadmap

## v0.1 (done)

- [x] Core: `awesome.yml` config (rubocop-style guards), runner, CLI,
      ameba-like output, `awesome doc`
- [x] **StructurePacking** — struct fields by decreasing alignment,
      computed sizes and concrete win ("24 → 16 bytes")
- [x] carat delivery: `binaries:` section, `carat install OrelSokolov/awesome.cr`

## v0.2 — search modes

Not every check is a guard with a verdict. Some questions are open-ended
("where does my code allocate?") — those deserve a **search mode**: a
smart grep through the compiler's AST instead of text regexes.

### `awesome search allocations`

Find every heap allocation in the program — smart grep via AST, not
text matching:

- `Foo.new` — class instantiation (heap); skip `struct .new`
- Array/Hash/Slice/Set literals (`[...] of`, `{...} =>`, `[] of`) and `+` on them
- String building: interpolation `"#{x}"`, `String#build`, `String#+` chains
- `to_s`/`inspect without an IO argument (implicit String allocation)
- `box`ing: procs capturing local vars, `Proc#closure`
- Boxed numerics, `Object#dup/clone`, `Array#new`-style constructors

Use case: audit a hot path for hidden GC pressure — allocations in audio
callbacks, frame loops, FFI shims — where text grep gives both false
positives (`new` in comments) and false negatives (literals don't say
"allocate").

Planned UX:

```console
$ awesome search allocations src/audio/*.cr
src/audio/driver.cr:42:9  Call#new   RingBuffer(Float32).new (heap)
src/audio/driver.cr:58:5  StringInterpolation  "#{ms}ms" (allocates)
...
3 files, 41 allocations
```

Searches get their own section in `awesome.yml`:

```yaml
search:
  allocations:
    exclude:
      - spec/**
```

## v0.3 — memory guards

C interop is where Crystal's GC stops helping: `LibFoo.malloc` memory
must be freed by hand. The memory family starts with the minimal,
zero-false-positive check and grows toward full lifecycle analysis.

- [x] **MemoryLeak** — a project calling a lib-shim allocator
      (`LibFoo.malloc` & co) must call the lib's deallocator at least
      once; the free may sit in any file (a reopened class's
      `#finalize` in another file covers the allocation). Works on the
      compiler's AST (`LibDef`/`FunDef`/`Call`) — no C parsing needed.
- [x] **DoubleFree** — the same variable passed to a lib-shim
      deallocator twice within one statement block with no
      reassignment in between. Pairing is per statement list, so frees
      in sibling `if`/`else` branches never fire.

### Later, memory

- Per-call pairing: prove every allocation site reaches a free, not
  just "at least one free exists in the project".
- Ownership transfer: `LibFoo.malloc` results wrapped in a
  finalizable class (`#finalize`/`#close`) count as freed.
- DoubleFree: pair `Pointer#free` (Crystal-side frees), not only
  lib-shim funs; free-after-`realloc` without reassignment.

## Later ideas

- `awesome search copies` — big structs passed by value (memcpy on every
  call; suggest pointer passing)
- StructurePacking: prove layouts of nested custom struct types
  (cross-file), not only builtins
- More guards, in the same spirit: semantic wins, zero false positives
- `--format json` for editor/CI integrations
