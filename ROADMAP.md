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

## Later ideas

- `awesome search copies` — big structs passed by value (memcpy on every
  call; suggest pointer passing)
- StructurePacking: prove layouts of nested custom struct types
  (cross-file), not only builtins
- More guards, in the same spirit: semantic wins, zero false positives
- `--format json` for editor/CI integrations
