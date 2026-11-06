# SubclassNoOverride

**Checks for inheritance of code instead of behaviour: a subclass that overrides none of its parent's methods just takes the implementation.**

## Why

A subclass that overrides nothing doesn't specialize anything —
through the parent's interface it *is* the parent. That means the
hierarchy exists to avoid copying code, not to model two variants of
one concept, and composition says it better: the taker holds a
collaborator instead of being one.

```crystal
class CachedRepo < Repo # overrides nothing — inheritance as copy-paste
end
```

## Examples

Good:

```crystal
class AuditedSave
  def initialize(@repo : Repo) # composition: have, don't be
  end

  def save(item)              # its own behaviour, delegating
    log(item)
    @repo.save(item)
  end
end
```

Bad:

```crystal
class Repo
  def save(item); end
end

class CachedRepo < Repo     # overrides nothing — only takes
  def cache_key(item); end
end
```

## What is skipped

- External parents (shards, stdlib) — their method list is unknowable
  from this codebase.
- Empty marker subclasses (no methods at all) — a separate case, not
  code reuse.
- Only the direct parent is compared; abstract parent methods count
  toward the intersection (they exist to be overridden).

## Config

```yaml
guards:
  SubclassNoOverride:
    enabled: true
```
