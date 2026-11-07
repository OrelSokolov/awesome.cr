# CliStdoutEpipe

**A CLI that dies the moment its stdout reader walks away — `foo | head` ends in `IO::Error: Broken pipe` instead of a quiet exit.**

## Why

When a CLI's stdout is a pipe and the reader exits early — `| head`
took its lines, `| less` was quit, an editor preview buffer stopped
reading — the next `write(2)` returns EPIPE and the Crystal runtime
raises `IO::Error`. Unhandled, that kills the process mid-report: the
output looks truncated "on some finding", stderr gets a trace, the
exit status is garbage. Real precedent: CRASH-001 — awesome itself
died on `awesome | head` until its entry point learned the rescue.

The handling is two lines at the entry point:

```crystal
rescue e : IO::Error
  exit(e.os_error == Errno::EPIPE ? 0 : 1) # reader gone — not an error
```

## Examples

Good:

```crystal
require "../src/tool"
begin
  exit Tool::CLI.run(ARGV)
rescue e : IO::Error
  exit(e.os_error == Errno::EPIPE ? 0 : 1) # reader gone — not an error
end
```

Bad:

```crystal
require "../src/tool"
exit Tool::CLI.run(ARGV) # `tool | head` → unhandled IO::Error mid-output
```

## What fires

- A collected file that writes to STDOUT at top level — `puts`,
  `print`, `p`/`pp`/`printf`, or any call on the `STDOUT` constant
  (`STDOUT << …`). A script.
- A binary declared in shard.yml (`binaries:` → `main:`): bin/** sits
  in the default exclude set, so the runner never collects these files
  — the guard reads them from disk itself. Any top-level call except
  `require` is the entry flow here: a binary that only forwards to its
  library (`exit Tool::CLI.run(ARGV)`) still needs the rescue.

## What is skipped

- A file that handles EPIPE syntactically, anywhere in it: a `rescue`
  naming `IO::Error`, or a reference to `Errno::EPIPE` / `Signal::PIPE`
  (`Signal.trap(Signal::PIPE) { exit 0 }` guards the whole process).
- Output inside defs, blocks, procs, classes, modules, libs or macros —
  per-file evidence must be a top-level write. A library that only
  prints from inside its methods is checked via its shard.yml binary
  entry point, not via its sources.
- Lowercase receivers (`stdout.puts …`) — syntax can't prove a local
  named `stdout` is the real STDOUT.
- Projects without a `binaries:` key in shard.yml — a library has no
  CLI to check. The key is looked up in the working directory.

## Config

```yaml
guards:
  CliStdoutEpipe:
    enabled: true
```
