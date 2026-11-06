# HardcodedDependency

**Checks that a class doesn't bypass an abstraction it itself uses — `SomeConcrete.new` inside a method, when the project already has the seam.**

## Why

Dependency inversion enforced where it is *provable*, all evidence
syntactic. When a project already declared a seam — one abstraction
with two or more implementations (`Store` with `MemoryStore` and
`RedisStore`, by subclassing or `include`) — and a class declares in
its own signature that it works with that abstraction
(`@store : Store`, `def rebuild(x : Store)`), then news up a concrete
implementation inside a method, the class contradicts itself: the
choice the type signature left open is welded shut one line below.
That's not a taste call — the seam exists and the line bypasses it.

```crystal
class Reporter
  def initialize(@store : Store) # injected — replaceable
  end

  def rebuild
    warm(MemoryStore.new)        # hardcoded — bypasses the Store seam
  end
end
```

Everything else is silent by design. An earlier version of this guard
guessed ("any project class constructed outside `initialize` is a
collaborator") and drowned real issues in false positives: a parser
building its result AST, a migration stamping `Time.now`, a script
creating an `HTTP::Client` — none of that is provably wrong from
syntax, so none of it is flagged. Constructing a type is a smell only
when the same class already promised to work with its abstraction.

## Examples

Good:

```crystal
class Reporter
  def initialize(@store : Store, @cache : Store) # both come from outside
  end

  def rebuild
    warm(@cache)
  end
end
```

Bad:

```crystal
class Reporter
  def initialize(@store : Store) # works with the abstraction…
  end

  def rebuild
    cache = MemoryStore.new      # …then welds one choice in
    cache.warm
  end
end
```

## What fires

All three must hold:

1. `SomeConcrete.new` inside a method of a class (not `initialize`,
   not a factory class-method).
2. `SomeConcrete` is one of ≥2 implementations of an abstraction
   *defined in the project* (a common superclass, or a module both
   `include`). External abstractions are cut off — their other
   implementations are unknowable from this codebase.
3. The same class declares the abstraction — or the constructed type,
   or a sibling — in a type annotation (`@store : Store`,
   `def f(x : Store)`, `@backup : MemoryStore`). Method *return* types
   don't count: `def pick : Store; MemoryStore.new; end` is a factory
   choosing an implementation, not a consumer bypassing a seam.

## What is skipped

- No seam (fewer than two implementations) — the construction might
  be exactly what the code means.
- The owner never declares the abstraction — maybe it genuinely needs
  that one concrete type.
- Project structs (value objects — data plumbing) and external types
  (shards, stdlib — no evidence available).
- `initialize` bodies, polymorphic construction (`klass.new`), factory
  class-methods (`def self.build`), exceptions (`raise X.new`),
  a class constructing itself or a type nested inside it.

## Config

```yaml
guards:
  HardcodedDependency:
    enabled: true
    allowed: [MemoryStore] # carve out exceptions: exact path,
                           # namespace prefix, or last segment
```
