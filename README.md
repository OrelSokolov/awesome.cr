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
$ awesome src foo.cr      # check specific paths
$ awesome doc             # documentation for all guards
$ awesome doc StructurePacking
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

## Development

```console
$ crystal spec        # run the test suite
$ crystal build bin/awesome.cr
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
