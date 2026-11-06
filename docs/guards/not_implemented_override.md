# NotImplementedOverride

**Checks for a subclass method whose whole body is `raise NotImplementedError.new(...)`, overriding a parent's concrete method of the same name.**

## Why

When the parent's method is concrete (it works), overriding it with a
raise doesn't specialize — it revokes. Through the parent's interface
the subclass claims to do what the parent does, then refuses at
runtime: exactly the "can't stand where the parent stood" Liskov
warns about. Either the behaviour doesn't apply to this variant
(then it shouldn't inherit it — compose instead), or the method is
really a contract (then the parent should declare `abstract def` and
let the compiler demand implementations).

```crystal
class Line < Shape
  def area
    raise NotImplementedError.new("lines have no area") # the promise, revoked
  end
end
```

## Examples

Good:

```crystal
class Shape
  def area
    compute_area # concrete — a promise to every caller
  end
end

class Circle < Shape
  def area # specializes — the promise holds
    Math::PI * @radius * @radius
  end
end
```

Bad:

```crystal
class Line < Shape
  def area # Shape#area is concrete — this only revokes it
    raise NotImplementedError.new("lines have no area")
  end
end
```

## What is skipped

- External parents (shards, stdlib) — their method list is unknowable
  from this codebase.
- Matches against the parent's `abstract def`s — implementing a
  contract with a raise is a compiler/coverage problem, not a broken
  promise.
- Bodies that do more than raise (`return 1 if @cached; raise ...`) —
  only a def whose *whole* body is the raise counts.
- Bare `raise "not implemented"` strings — only the type itself
  says "not implemented".

## Config

```yaml
guards:
  NotImplementedOverride:
    enabled: true
```
