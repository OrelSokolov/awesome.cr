#!/usr/bin/env crystal
# Binary entry point (see shard.yml → carat binaries).
require "../src/awesome"
begin
  exit Awesome::CLI.run(ARGV)
rescue e : IO::Error
  # Our stdout reader walked away (`awesome | head`, less quit): not an
  # error — exit quietly (CRASH-001). Any other IO::Error stays one.
  exit(e.os_error == Errno::EPIPE ? 0 : 1)
end
