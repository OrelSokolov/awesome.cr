# BoolFlagParameter

**Checks for Bool parameters that call sites feed with both literal `true` and literal `false` — a method doing two jobs, named by its flag.**

## Why

A flag argument means the method body branches on it, and each branch
is a behaviour. When callers pass both literals, both behaviours are
real — and every call site has to be read to the end
(`sync.run(false)`) to learn which one happens. Two methods say the
same thing without the branch (`sync` / `sync!`) and keep the call
sites self-describing.

The guard fires only on observed evidence — both literals must
appear at real call sites in the project. Plenty of Bool params are
legitimately one-sided (a `quiet : Bool = false` nobody flips), and
the parameter's mere existence proves nothing.

## Examples

Good:

```crystal
class Sync
  def sync! # destructive — its own name, no flag to read
    rebuild_index
  end

  def sync # safe — same class, two honest methods
    copy_files
  end
end
```

Bad:

```crystal
class Sync
  def run(force : Bool) # one name, two behaviours
    force ? rebuild_index : copy_files
  end
end

Sync.new.run(true)  # the branch callers actually take,
Sync.new.run(false) # spelled out at every call site
```

## What is skipped

- One-sided flags — a literal seen on only one side (or no literals
  at all) is not evidence of two behaviours.
- Same-named methods — when several defs share the name in the
  project, a literal at a call site can't be pinned to one of them.
- `initialize` defs (`Foo.new(true)` can't be attributed by name
  alone) and operator names (`==`, `[]`, ...).
- Parameters named `default` — a value, not a branch (config readers
  pass both literals legitimately).
- Parameters without a `Bool` restriction — untyped flags aren't
  provably flags.

## Config

```yaml
guards:
  BoolFlagParameter:
    enabled: true
    allowed: [] # param names never flagged (e.g. [quiet])
```
