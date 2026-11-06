# LogEagerInterp

**Checks for `log.info "x=#{x}"` — an eager String built for a log call that may never log it.**

## Why

`log.info "x=#{x}"` interpolates before the call happens, so the
String is allocated even when the info level is disabled in
production. The block form is lazy by contract: `log.info { "x=#{x}" }`
runs the interpolation only if the level is actually emitted.

## Examples

Good:

```crystal
log.info { "x=#{x}" }   # lazy: built only if emitted
```

Bad:

```crystal
log.info "x=#{x}"       # eager: allocated even when muted
```

## What is skipped

- Receivers other than `log`/`logger` (`@log` included) — for
  anything else the block form's meaning is not ours to promise.

## Config

```yaml
guards:
  LogEagerInterp:
    enabled: true
```
