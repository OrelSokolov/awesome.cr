# SingleCharStringArg

**Checks for one-character String literals where a Char overload exists.**

## Why

`String#includes?`, `#split`, `#starts_with?`, `#ends_with?`,
`#replace`, `#sub` and `#gsub` all have Char overloads next to their
String ones. `s.split(",")` slices on a String separator — length
checks, byte-wise compares; `s.split(',')` compares one character
code. Free win, zero semantic change.

## Examples

Good:

```crystal
parts = path.split('/')
broken = text.gsub('a', 'b')
```

Bad:

```crystal
parts = path.split("/")
broken = text.gsub("a", "b")
# String separator: length checks + string compare
# where a character compare would do
```

## What is skipped

- Multi-character strings and non-literal arguments — only provable
  single-character literals fire.

## Config

```yaml
guards:
  SingleCharStringArg:
    enabled: true
```
