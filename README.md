# awesome

**Is your Crystal code awesome — or awful?**

`awesome` is a next-generation semantic linter for Crystal. Where ameba
checks style, awesome checks **semantics and real best practices** — the
kind of things that make code faster or slower, not just prettier.

- **Guards, not cops.** Every check is a guard: semantic, documented,
  configured in `awesome.yml` (rubocop.yml-style).
- **The compiler's own AST.** awesome parses with `Crystal::Parser` —
  the exact AST `crystal build` sees. No reimplementation, no drift.
- **Documentation lives in the guard.** `awesome doc` prints each
  guard's short description, good example and bad example — straight
  from the source of truth.
- **Zero dependencies.** Just Crystal.

## Install

With [carat](https://github.com/OrelSokolov/carat.cr):

```console
$ carat install OrelSokolov/awesome.cr
$ awesome
```

Or from a checkout:

```console
$ git clone https://github.com/OrelSokolov/awesome.cr && cd awesome.cr
$ crystal build --release bin/awesome.cr -o bin/awesome
```

## Usage

```console
$ awesome                 # check the current directory (all guards)
$ awesome speed           # speed guards only
$ awesome memory src lib/ # memory guards on specific paths
$ awesome smell src/      # smell guards only
$ awesome src foo.cr      # check specific paths
$ awesome doc             # documentation for all guards
$ awesome doc StructurePacking
$ awesome guards          # registered guards: total and by kind
```

Output:

```console
src/demo.cr:1:1
[StructurePacking] Reorder struct fields by decreasing alignment (largest first): sizeof can shrink from 56 to 48 bytes
> struct Frame

1 inspected, 1 issue.
Your code is awful: 1 issue.
```

Exit status: `0` — awesome, `1` — awful, `2` — error. CI-ready.

## Configuration

Drop an `awesome.yml` in your project root (rubocop.yml-style, guards
instead of cops). Without one, awesome runs all guards with sane
defaults:

```yaml
include:
  - src/**/*.cr

exclude:
  - lib/**

guards:
  StructurePacking:
    enabled: true
    check_extern: false
```

## Guards

| Guard | Kind | Checks | Docs |
|---|---|---|---|
| StructurePacking | memory | Struct fields ordered by decreasing alignment — no bytes wasted on padding | [docs/guards/structure_packing.md](docs/guards/structure_packing.md) |
| MemoryLeak | memory | C heap allocations from lib shims (`Lib*.malloc`) paired with a matching free in the file | [docs/guards/memory_leak.md](docs/guards/memory_leak.md) |
| DoubleFree | memory | The same pointer never passed to a lib-shim deallocator twice without a reassignment in between | [docs/guards/double_free.md](docs/guards/double_free.md) |
| BoolBitmask | memory | Structs with many Bool fields — a `@[Flags]` enum packs the same flags into one byte | [docs/guards/bool_bitmask.md](docs/guards/bool_bitmask.md) |
| FileReadLines | memory | `File.read_lines` slurps the whole file; `File.each_line` streams with flat memory use | [docs/guards/file_read_lines.md](docs/guards/file_read_lines.md) |
| InterpIntoIo | memory | Interpolation inside IO calls (`io << "a#{b}c"`) — append the parts separately, zero intermediate Strings | [docs/guards/interp_into_io.md](docs/guards/interp_into_io.md) |
| LogEagerInterp | memory | `log.info "x=#{x}"` interpolates even when muted; the block form is lazy | [docs/guards/log_eager_interp.md](docs/guards/log_eager_interp.md) |
| ToSWithoutIo | memory | `def to_s` without arguments — `io <<`, interpolation and `puts` all call `to_s(io : IO)` instead | [docs/guards/to_s_without_io.md](docs/guards/to_s_without_io.md) |
| NilableStructField | memory | Nilable fields in structs are tagged unions — `Int64?` is 16 bytes plus a branch, not 8 | [docs/guards/nilable_struct_field.md](docs/guards/nilable_struct_field.md) |
| AggregateAfterTransform | speed | `xs.map { … }.sum`/`.size`/`.empty?` — the intermediate Array is pure garbage | [docs/guards/aggregate_after_transform.md](docs/guards/aggregate_after_transform.md) |
| ArrayConcatInLoop | speed | `arr += [x]` inside loops copies the whole Array every iteration; `arr << x` appends in place | [docs/guards/array_concat_in_loop.md](docs/guards/array_concat_in_loop.md) |
| ArrayShiftInLoop | speed | Array#shift/#unshift inside loops are O(n) per call — Deque is O(1) at both ends | [docs/guards/array_shift_in_loop.md](docs/guards/array_shift_in_loop.md) |
| MapCompact | speed | `xs.map { … }.compact` — `compact_map` builds the result in one pass | [docs/guards/map_compact.md](docs/guards/map_compact.md) |
| MapFlatten | speed | `xs.map { … }.flatten` — `flat_map` does one pass, no intermediate Array | [docs/guards/map_flatten.md](docs/guards/map_flatten.md) |
| SelectCompareZero | speed | `xs.select { … }.size == 0` — `none?`/`any?` answer without the filtered Array | [docs/guards/select_compare_zero.md](docs/guards/select_compare_zero.md) |
| SelectFirst | speed | `xs.select { … }.first` — `find` stops at the first match, allocates nothing | [docs/guards/select_first.md](docs/guards/select_first.md) |
| SelfSortReassign | speed | `xs = xs.sort` — the bang version does the same job in place (advisory) | [docs/guards/self_sort_reassign.md](docs/guards/self_sort_reassign.md) |
| SingleCharStringArg | speed | Single-character String literals where a Char overload exists (`split(",")` → `split(',')`) | [docs/guards/single_char_string_arg.md](docs/guards/single_char_string_arg.md) |
| StringConcatInLoop | speed | `s += "…"` inside loops — append into IO::Memory, materialize once after the loop | [docs/guards/string_concat_in_loop.md](docs/guards/string_concat_in_loop.md) |
| TimesIndex | speed | `xs.size.times { |i| xs[i] }` — `each` yields the element, no bounds check | [docs/guards/times_index.md](docs/guards/times_index.md) |
| UnusedIndex | speed | `each_with_index` with an index nobody reads — plain `each` skips the bookkeeping | [docs/guards/unused_index.md](docs/guards/unused_index.md) |
| HardcodedDependency | smell | A class constructing its own dependencies (`SomeConcrete.new` outside `initialize`) instead of accepting them via the constructor | [docs/guards/hardcoded_dependency.md](docs/guards/hardcoded_dependency.md) |
| GodClass | smell | A class carrying too many responsibilities — measured by method count (25) and instance-variable count (10) | [docs/guards/god_class.md](docs/guards/god_class.md) |
| DeepInheritance | smell | Inheritance chains three or more levels deep (hops between project classes; external parents cap the chain) | [docs/guards/deep_inheritance.md](docs/guards/deep_inheritance.md) |
| SingleSubclass | smell | A non-abstract base with exactly one subclass — speculative hierarchy | [docs/guards/single_subclass.md](docs/guards/single_subclass.md) |
| SubclassNoOverride | smell | A subclass overriding none of its parent's methods — inheritance for code reuse, not polymorphism | [docs/guards/subclass_no_override.md](docs/guards/subclass_no_override.md) |
| UtilityClass | smell | A class whose methods are all `def self.` with no instance behaviour — a namespace that should be a module | [docs/guards/utility_class.md](docs/guards/utility_class.md) |
| LongParameterList | smell | A method taking more parameters than a call site can read (default 7) — bundle them or split the method | [docs/guards/long_parameter_list.md](docs/guards/long_parameter_list.md) |
| NotImplementedOverride | smell | A subclass overriding a parent's concrete method with only `raise NotImplementedError` — the promise, revoked (LSP) | [docs/guards/not_implemented_override.md](docs/guards/not_implemented_override.md) |
| BoolFlagParameter | smell | A Bool parameter fed both literal `true` and `false` at call sites — two behaviours behind one name | [docs/guards/bool_flag_parameter.md](docs/guards/bool_flag_parameter.md) |

## Development

```console
$ crystal spec        # run the test suite
$ crystal build bin/awesome.cr
```

[examples/awful/](examples/awful) is a live demo: the bad snippets of
every guard, one file per guard (a file may hold several examples of
its guard). `crystal spec` asserts each guard fires on its own file —
and nothing else fires there; run the binary to see the report:

```console
$ bin/awesome examples/awful
```

A guard is a class in `src/awesome/guards/`:

```crystal
class Awesome::Guards::MyGuard < Awesome::Guard
  KIND              = "speed" # or "memory"
  SHORT_DESCRIPTION = "..."
  GOOD_EXAMPLE      = "..."
  BAD_EXAMPLE       = "..."

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = MyVisitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end
end

Awesome::Guard.registered << Awesome::Guards::MyGuard
```

See [ROADMAP.md](ROADMAP.md) for what's next (search modes, more guards).

## License

MIT — see [LICENSE](LICENSE).
