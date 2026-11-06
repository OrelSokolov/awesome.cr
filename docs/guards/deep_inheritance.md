# DeepInheritance

**Checks for inheritance chains three or more levels deep — every level adds contracts the levels below must honour; composition expresses reuse without the coupling.**

## Why

A chain three levels deep almost always means "wanted to reuse code",
not "is a kind of". Deep hierarchies are fragile: behaviour spreads
across files, contracts accumulate, and every change ripples down.
Composition states the same intent locally — a class *holding* the
collaborators whose code it needs.

```crystal
class C < B; end  # B < A: which of A and B does C actually honour?
                  # Unknown without reading both files.
```

## Examples

Good:

```crystal
class Parser
  def initialize(@lexer : Lexer) # composition: have, don't be
  end
end
```

Bad:

```crystal
class A; end
class B < A; end
class C < B; end # 2 hops deep — have A/B instead of being them
```

## What is skipped

- External parents cap the chain: `MyA < MyB < Kemal::Base` counts as
  depth 2 (one visible hop) — what lies beyond project code is
  unknowable from syntax.
- Exception hierarchies and whitelisted stdlib bases (`Exception`,
  `Reference`, `Object`, `Struct`, `Enum`, `Value`, `IO`, `Comparable`,
  `Enumerable`) — deep stdlib taxonomies are normal, not a smell.
- Ambiguous parent names (several same-named types in the project) —
  unresolved means uncounted.

## Config

```yaml
guards:
  DeepInheritance:
    enabled: true
    max_depth: 2                   # visible hops before firing
    allowed_superclasses: [Exception, Reference, Object, ...]
```
