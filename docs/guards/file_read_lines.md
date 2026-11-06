# FileReadLines

**Checks for `File.read_lines(…)` — slurping a whole file to walk its lines.**

## Why

Rust lore: `BufReader::lines` streams; `read_to_string` slurps.
`File.read_lines(path)` in Crystal reads the whole file into memory,
then allocates a String per line, all up front — for a big input that
is peak memory proportional to the file size. `File.each_line(path)`
yields line by line from a buffered read, so peak memory stays flat.

## Examples

Good:

```crystal
File.each_line(path) do |line|
  process line
end
```

Bad:

```crystal
File.read_lines(path).each do |line|
  process line
end
# whole file + every String already in memory
```

## What is skipped

- Nothing — but if you genuinely need the whole Array (random access,
  re-iteration), ignore the finding.

## Config

```yaml
guards:
  FileReadLines:
    enabled: true
```
