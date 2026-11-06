# UtilityClass

**Checks for classes that are namespaces in disguise: every method is `def self.`, with no instance behaviour — never usefully instantiated.**

## Why

A class whose methods are all class-level and that declares no
`initialize`, no instance defs and no field macros is a bag of names.
Nothing distinguishes it from a namespace, and Crystal's spelling for
a namespace is `module`. The switch is free: every `Klass.method`
call site stays valid, and `Klass.new` was meaningless anyway — there
is nothing to instantiate.

```crystal
class Registry           # never instantiated — a module in disguise
  def self.load(path); end
end
```

## Examples

Good:

```crystal
module Registry         # a namespace, honestly
  def self.load(path)
  end
end
```

Bad:

```crystal
class Registry
  def self.load(path)
  end

  def self.save(path, data)
  end
end
```

## What is skipped

- Any instance behaviour — one instance def, `initialize`, a
  getter/property, or an instance macro means the class is
  instantiable and the verdict is off.
- A superclass — inherited behaviour is unknowable from syntax.
- A `def self.new` factory — construction through it is meaningful,
  and a module can't take its place.
- Structs (value types carry data, not roles), modules (already the
  honest spelling) and empty classes (no namespace evidence).

## Config

```yaml
guards:
  UtilityClass:
    enabled: true
```
