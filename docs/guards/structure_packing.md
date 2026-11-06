# StructurePacking

**Checks that struct fields are ordered by decreasing alignment, so the struct wastes no bytes on padding.**

## Why

Crystal lays struct fields out in **declaration order**, giving each field
its natural alignment (C ABI rules) — the compiler never reorders fields
to minimize padding. That makes field order a real performance lever:

```crystal
struct A                # struct B
  getter a : UInt8      #   getter a : Int64
  getter b : Int64      #   getter b : UInt8
end                     # end
# sizeof(A) == 16       # sizeof(B) == 16? No — 24!
```

`B` pays 8 bytes of padding because the `Int64` must sit on an 8-byte
boundary. Wider-first ordering gives smaller structs: less memory, fewer
cache misses. On ARM targets (Android, Raspberry Pi) the effect is even
more tangible — NEON loads dislike sparse data.

Crystal side, verified on Crystal 1.21: fields follow natural alignment
exactly as the guard models it.

## Examples

Good:

```crystal
struct Pixel
  getter value : Int64     # widest first
  getter red : Int32
  getter green : UInt8
  getter blue : UInt8
end
# sizeof == 16, no padding
```

Bad:

```crystal
struct Pixel
  getter red : UInt8       # narrow first…
  getter value : Int64     # …forces padding around the Int64
  getter green : UInt8
  getter blue : UInt8
end
# sizeof == 24 (8 bytes of padding) — should be 16
```

## What is skipped

- `@[Packed]` / `@[Alignment(n)]` structs — you manage their layout explicitly.
- `@[Extern]` structs — they must mirror a C header byte-for-byte; enable
  with `check_extern: true` if you control the header too.
- Structs where any field's layout cannot be proven from builtin types
  alone (custom structs, enums, `getter x` without a type annotation).
  Conservative on purpose: no false positives.

## Config

```yaml
guards:
  StructurePacking:
    enabled: true
    check_extern: false
```
