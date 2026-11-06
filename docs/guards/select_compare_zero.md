# SelectCompareZero

**Checks for `xs.select { … }.size == 0` — a filtered Array built just to be compared with zero.**

## Why

`xs.select { |x| x > 1 }.size == 0` materializes the whole filtered
Array to count it, then throws it away for a boolean.
`xs.none? { |x| x > 1 }` answers the same question by
short-circuiting on the first match — no allocation, no full pass.
`.size > 0` is `any?`; `.empty?` on a select is `none?`.

## Examples

Good:

```crystal
return if items.none? { |item| item.invalid? }
proceed if items.any? { |item| item.urgent? }
```

Bad:

```crystal
return if items.select { |item| item.invalid? }.size == 0
proceed if items.select { |item| item.urgent? }.size > 0
#        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ filtered Array
#        allocated, counted, discarded
```

## Config

```yaml
guards:
  SelectCompareZero:
    enabled: true
```
