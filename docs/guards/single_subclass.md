# SingleSubclass

**Checks for speculative hierarchy: a non-abstract base class with exactly one subclass — inheritance "for the future" that never came.**

## Why

A base with a single subclass adds a level of indirection with nothing
to choose between: the second implementation was planned, never
written, and now every reader pays the hop. The usual resolutions are
composition (the subclass *has* a collaborator instead of *being* a
base) or merging the two back into one class — either way the
hierarchy stops pretending.

## Examples

Good:

```crystal
class Report
  def initialize(@source : DataSource) # composition over hierarchy
  end
end
```

Bad:

```crystal
class ReportBase; end          # exists only to be inherited

class Report < ReportBase; end # the only subclass — merge them
```

## What is skipped

- Abstract bases — a contract written for extension is legitimate even
  with one implementation.
- Bases defined outside the project — their full set of subclasses is
  unknowable from this codebase.
- Bases with two or more subclasses — that's just inheritance.

## Config

```yaml
guards:
  SingleSubclass:
    enabled: true
```
