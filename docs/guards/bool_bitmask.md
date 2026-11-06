# BoolBitmask

**Checks for structs with many Bool fields — a pack of Bools is a poor man's bitmask.**

## Why

Rust's `bitflags` crate packs flags into one integer; in Crystal a
`@[Flags]` enum does the same. Each `Bool` struct field costs a full
byte, so four flags cost 4 bytes, while a `@[Flags]` enum costs 1.
Fewer bytes also means cheaper copies and better cache density for
arrays of such structs.

## Examples

Good:

```crystal
@[Flags]
enum Permissions
  Readable
  Writable
  Executable
  Sticky
end

struct Entry
  getter mode : Permissions  # 4 flags in 1 byte
end
```

Bad:

```crystal
struct Entry
  getter readable : Bool     # 4 flags = 4 bytes
  getter writable : Bool
  getter executable : Bool
  getter sticky : Bool
end
```

## What is skipped

- Structs annotated `@[Extern]` — their layout mirrors C.
- Structs below `min_bools` Bool fields.

## Config

```yaml
guards:
  BoolBitmask:
    enabled: true
    min_bools: 4                  # fire at this many Bool fields
```
