#!/usr/bin/env crystal
# Binary entry point (see shard.yml → carat binaries).
require "../src/awesome"
exit Awesome::CLI.run(ARGV)
