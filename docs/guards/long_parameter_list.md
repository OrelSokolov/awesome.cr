# LongParameterList

**Checks for methods taking more parameters than a call site can read (default 7) — stated as a fact, not a verdict.**

## Why

The method-level twin of GodClass: whether a list is "too long" isn't
semantic, but the working-memory window isn't endless. Past ~7
parameters a call site becomes unreadable, and every parameter after
that is usually part of a concept begging to be its own type — a
`Message`, a `PageSetup`. The message states the count and the two
honest fixes; whether to apply them is the author's call.

```crystal
mailer.send(to, from, subject, body, cc, bcc, reply_to, attachments) # which arg is which?
```

## Examples

Good:

```crystal
class Mailer
  def send(message : Message) # one concept — the parameters travel together
  end
end

struct Message
  getter to : String
  getter subject : String
end
```

Bad:

```crystal
class Mailer
  def send(to, from, subject, body, cc, bcc, reply_to, attachments)
    # 8 parameters — a Message struct wants to exist
  end
end
```

## What is skipped

- Nothing by kind: `initialize`, `def self.` methods, abstract defs,
  struct and module methods all count — a wide constructor is as
  wide as a wide method. `*rest` counts as one parameter; the block
  argument doesn't count.

## Config

```yaml
guards:
  LongParameterList:
    enabled: true
    max_params: 7 # fire above this many parameters (5 = strict)
```
