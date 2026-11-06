# GodClass

**Checks for classes carrying too many responsibilities, measured by two proxy metrics: method count and instance-variable count.**

## Why

Single Responsibility can't be verified from syntax — but two honest
proxies can: a class with dozens of methods or a double-digit pile of
instance variables is doing many jobs whether or not it "should". Many
ivars usually mean many unrelated state machines; many methods usually
mean several services fused together.

The guard states facts (`"27 methods, 12 ivars"`), not a verdict —
whether to split is the author's call. Thresholds are configurable and
the defaults are deliberately high, so only outliers are flagged.

Counts span the whole project: a class reopened in another file is one
class, its fragments' methods and ivars merge — splitting a god class
over two files doesn't hide it.

## Examples

Good:

```crystal
class Cart
  getter items = [] of Item   # 2 methods, 1 ivar — one job

  def add(item : Item)
    items << item
  end

  def total : Int32
    items.sum(&.price)
  end
end
```

Bad:

```crystal
class Order          # 27 methods, 12 ivars — pricing, shipping,
  # ...              # emails and auditing all live here
end
```

## What is skipped

- Structs — value types carry data, not roles.
- Modules — namespaces, not classes.
- Nothing else: abstract classes are measured too (contracts attract
  methods), and nested classes count for themselves, not their outer
  class.

## Config

```yaml
guards:
  GodClass:
    enabled: true
    max_methods: 25
    max_ivars: 10
```
