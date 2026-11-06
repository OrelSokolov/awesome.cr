# HardcodedDependency

**Checks that classes don't construct their own dependencies — `SomeConcrete.new` outside `initialize` means a welded-in collaborator.**

## Why

The one SOLID letter that is mechanically detectable (D — Dependency
Inversion): when a class calls `Engine.new` itself, the dependency can
neither be substituted in tests nor reconfigured at runtime. The class
is responsible for *using* its collaborators, not *creating* them —
creation belongs to the composition root (`main`, the DI container),
and the class should say what it needs:

```crystal
class Car
  def initialize(@engine : Engine) # injected
  end
end
```

## Examples

Good:

```crystal
class Car
  def initialize(@engine : Engine) # injected — replaceable in tests
  end

  def start
    @engine.run
  end
end
```

Bad:

```crystal
class Car
  def start
    engine = Engine.new # hardcoded — welded-in dependency
    engine.run
  end
end
```

## What is skipped

- `initialize` bodies — assigning fields there is the norm.
- Polymorphic construction (`klass.new`, `foo.new`) — the receiver is
  not a constant path, so it *is* injected.
- Factory class-methods (`def self.build` with a receiver) — building
  objects is their job.
- Exceptions (`raise X.new`, names ending in `Error`/`Exception`).
- A class constructing itself or a type nested inside it (private
  helpers like an AST `Visitor`).
- Structs — value types carry data, not collaborators.
- The `allowed` whitelist — stdlib data types by default (`Array`,
  `Hash`, `Set`, `Deque`, `Slice`, `String`, `IO`, `Time`, `Random`,
  `Crystal`); config entries extend it, matching the written path
  exactly, as a namespace prefix, or by last segment.

## Config

```yaml
guards:
  HardcodedDependency:
    enabled: true
    allowed: [MessageBus, MyFramework] # paths or namespaces
    min_dependencies: 1                # per class, fire from N hits
```
