# Plan: Rust-inspired performance guards for awesome.cr

Add 8 new guards in the spirit of `StructurePacking` (Rust-community perf
lore translated to checks over the Crystal AST). Architecture is fixed by
the existing codebase: each guard is `src/awesome/guards/<name>.cr`
subclassing `Awesome::Guard` with `SHORT_DESCRIPTION` / `GOOD_EXAMPLE` /
`BAD_EXAMPLE` constants (docs are carried by the class itself, `awesome
doc` renders them), a spec file next to `spec/structure_packing_spec.cr`,
and config keys read via `config.bool/int` from `awesome.yml`.

## Phase 1 — memory-layout family (companions to StructurePacking)

### 1. `NilableStructField` — `src/awesome/guards/nilable_struct_field.cr`
- Rust angle: `Option<i64>` is niche-optimized to 8 bytes; in Crystal
  `Int64?` is a tagged union `{Int32 tag, Int64 value}` = 16 bytes plus a
  branch on every access.
- Check: walk `ClassDef` where `struct?`; reuse the field-collection
  pattern from `StructurePacking` (`TypeDeclaration` + `property/getter`
  macros). Fire when a declared type is a `Crystal::Union` that includes
  a `Nil` member.
- Conservative (no false size claims): only fire when every other union
  member is a provable builtin from a `PRIMITIVES`-style table (copy the
  table; guards stay standalone per project style). Message states the
  actual cost, e.g. "…doubles the field (8 → 16 bytes) and adds a branch;
  prefer a sentinel value or a separate Bool flag".
- Skip structs annotated `@[Extern]` (layout mirrors C anyway).

### 2. `BoolBitmask` — `src/awesome/guards/bool_bitmask.cr`
- Rust angle: the `bitflags` crate — N Bools = N bytes, one flags-enum = 1.
- Check: struct field declarations of type `Bool`; when count ≥
  `min_bools` (config int, default 4), suggest a `@[Flags]` enum.
- Message mentions the saving (`4 Bools → 1 UInt8`).

## Phase 2 — allocation traps in loops (clippy::perf style)

Shared helper logic (private, duplicated per guard to match the
standalone-guard style): a `Crystal::Visitor` subclass that tracks loop
depth — increment on `While`, `Until`, and `Call` with a `Block` whose
name is in a common-iterator set (`times`, `each`, `each_with_index`,
`map`, `loop`, `upto`, `downto`, `step`). Missing a rare iterator → false
negative, which is fine; false positives are not.

### 3. `StringConcatInLoop` — `src/awesome/guards/string_concat_in_loop.cr`
- Rust angle: clippy `string_add_assign` — repeated `String` allocation;
  use `String::with_capacity`/`push_str`. Crystal: `IO::Memory` /
  `String::Builder`.
- Check: inside a loop, `OpAssign` with op `+` on a `Var`/`InstanceVar`
  where the value is a `StringLiteral` or `StringInterpolation`; also the
  spelled-out `Assign(Var, Call(+, Var, StringLiteral))`.

### 4. `ArrayShiftInLoop` — `src/awesome/guards/array_shift_in_loop.cr`
- Rust angle: `VecDeque` instead of `Vec::remove(0)` — O(1) both ends.
  Crystal: `Deque`.
- Check: inside a loop, `Call` named `shift` or `unshift` with an explicit
  receiver. Message: "Array#shift is O(n); use Deque for queue access".

### 5. `SelfSortReassign` — `src/awesome/guards/self_sort_reassign.cr`
- Rust angle: clippy `redundant_clone` — sort in place instead of
  reallocating (`v.sort()` / `sort_unstable`).
- Check: `Assign` where target is a `Var` and value is a `Call` (no
  block, no args) on the *same* var name with method in `sort, uniq,
  reverse, shuffle, rotate`. Suggest the `!` version; wording is advisory
  ("…if nothing else holds a reference").

## Phase 3 — cheap mechanical wins

### 6. `UnusedIndex` — `src/awesome/guards/unused_index.cr`
- Rust angle: clippy `unused_enumerate_index`.
- Check: `Call` `each_with_index` with a `Block` whose args are exactly
  two, where the second arg name never appears as a `Var` in the block
  body → suggest plain `each`.

### 7. `FileReadLines` — `src/awesome/guards/file_read_lines.cr`
- Rust angle: `BufReader::lines` instead of `read_to_string` — stream,
  don't slurp.
- Check: `Call` `read_lines` on a `Path`/const receiver `File`. Suggest
  `File.each_line` / `#each_line`.

### 8. `MapFlatten` — `src/awesome/guards/map_flatten.cr`
- Rust angle: clippy `map_flatten` → `flat_map`.
- Check: `Call` `flatten` (no args, no block) whose `obj` is a `Call`
  `map` with a block → suggest `flat_map`.

## Explicitly out of scope (heuristic, noisy — listed as follow-ups only)
`StructInsteadOfClass`, `EnumBaseType`, `HashInitialCapacity` — semantics
can't be proven from syntax alone; revisit later, maybe as advisory level.

## Wiring & verification (after each phase)
1. `crystal spec` — new specs green, existing ones untouched.
2. Spec helper: generalize `pack_issues` in `spec/spec_helper.cr` into
   `guard_issues(guard_class, code, config_yaml = nil)` keeping
   `pack_issues` as a thin wrapper so the existing spec keeps working.
3. Smoke-run the linter on this repo itself:
   `crystal run src/awesome.cr -- --only <NewGuard> src` (self-hosting
   check for false positives on real code, incl. the new guards' own
   sources).
4. `crystal run src/awesome.cr -- doc <GuardName>` to eyeball rendered
   docs.
5. Add `BoolBitmask.min_bools` (and nothing else) to `awesome.yml` only
   if a non-default value is wanted — defaults live in code.

## New specs (one file per guard, mirroring structure_packing_spec.cr)
- happy path (no issues) + flagged case asserting `line` and message
  fragments, plus the specific skip cases listed above (Extern, unprovable
  types, non-loop context, non-matching receivers, etc.).
