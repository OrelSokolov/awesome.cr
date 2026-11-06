# NilableStructField

**Checks for nilable fields inside structs — a tagged union where a payload would do.**

## Why

Rust's `Option<i64>` is niche-optimized down to 8 bytes; Crystal has
no niche optimization, so `Int64?` is a tagged union
`{Int32 type_id, Int64 value}` — 16 bytes (with padding) and a branch
on every access. On hot structs a sentinel value (an "impossible"
value of the payload type) or a separate Bool flag keeps the field at
its natural size and the access branch-free.

## Examples

Good:

```crystal
struct Session
  getter id : Int64       # absent sessions use ID 0
  getter closed : Bool    # explicit state instead of nil
end
```

Bad:

```crystal
struct Session
  getter id : Int64?      # 16 bytes + a branch, not 8
  getter closed : Bool
end
```

## What is skipped

- Structs annotated `@[Extern]` — their layout mirrors C.
- Unions whose non-nil members are not all provable builtins — the
  byte cost stated in the message is always exact, so unprovable
  types mean no firing (a false negative beats a wrong size claim).

## Config

```yaml
guards:
  NilableStructField:
    enabled: true
```
