# Line-by-line allocation report (`awesome allocations`).
#
# Every code line of the inspected set gets one of three statuses:
#
#   red   — the line allocates: an allocation construct sits on it
#           (an Array literal, a String interpolation, `Foo.new`,
#           `LibC.malloc`, `xs.map { … }` …), or it calls a method
#           that (transitively) allocates. The `def` line of an
#           allocating method is red too, even though other lines of
#           its body may be green.
#   green — provably allocation-free: no allocation construct and no
#           call whose target is unknown or allocating.
#   gray  — undefined: a call whose target cannot be found in the
#           current scope (the stdlib, a shard, another file in file
#           scope). We honestly don't know what it does — it needs
#           investigation, so neither red nor green is claimed.
#
# Recursion is a fixpoint over the syntactic call graph: a method is
# allocating when its body holds an allocation construct or a call to
# an allocating method; cycles and self-recursion converge (a clean
# recursive method stays green). Resolution is by method name across
# the scope, like `Awesome::Index`: overloads written in the project
# merge — if any of them allocates, the call is red (conservative,
# better a false red than a false green).
#
# Two scopes (`--scope`):
#
#   project — calls resolve against defs from every collected file:
#             the accurate report for the whole project. Stdlib and
#             shard calls are still gray — their bodies are outside
#             the indexed code.
#   file    — calls resolve against defs from the same file only:
#             the quick first-pass version. A call to a method defined
#             in another file of the same project is gray here, so the
#             report is deliberately less precise.
#
# The analysis is syntactic (no type inference), so it is conservative
# by design: `red` reads "allocates (or may allocate)", `green` reads
# "provably does not". String literals are green — Crystal
# deduplicates them into static data, they cost nothing at the call
# site (an interpolation, not a literal, is what allocates). Closures
# and macros are not expanded; see the limitations in the README.
#
# The collecting visitor lives in allocations/collector.cr, the
# fixpoint and per-line statuses in allocations/analyzer.cr.
module Awesome::Allocations
  # Line statuses, ordered worst-last: merging two statuses (a line
  # with several marks, a def with several body lines) takes the worse
  # one — Red > Gray > Green.
  enum Status
    Green = 0
    Gray  = 1
    Red   = 2

    def worse(other : Status) : Status
      value >= other.value ? self : other
    end
  end

  SCOPES = {"file", "project"}

  # The report for one source file: its code lines and the status of
  # each (parallel arrays; `lines.size == statuses.size`).
  class FileReport
    getter path : String
    getter lines : Array(String)
    getter statuses : Array(Status)

    def initialize(@path, @lines, @statuses)
    end

    def count(status : Status) : Int32
      @statuses.count(&.==(status))
    end
  end

  # One call whose target must be resolved before the line can be
  # classified: the call name is not a known allocation construct and
  # not a pure compiler builtin (those never become call sites).
  record CallSite, line : Int32, name : String

  # A `def` (or `fun`) with its line span: the def line itself plus
  # the body range used to attribute call sites to it. `fun` defs are
  # containers for their body's marks but cannot be called by name
  # from Crystal code, so they never resolve as call targets.
  class DefInfo
    property name : String
    property def_line : Int32
    property start_line : Int32
    property end_line : Int32
    property resolvable : Bool
    # Names of the call sites inside the body range, filled by the
    # analyzer (the collector keeps calls file-wide).
    property body_calls = [] of String
    property? direct : Bool
    # The def's fixpoint state (Red/Gray/Green of the whole body),
    # written back by the analyzer and applied to the def line.
    property state : Status = Status::Green

    def initialize(@name, @def_line, @start_line, @end_line,
                   @resolvable = true, @direct = false)
    end

    def covers?(line : Int32) : Bool
      (@start_line..@end_line).covers?(line)
    end
  end

  # Classifies every line of every source: the entry point used by
  # `awesome allocations`. `scope` is one of SCOPES ("project" is the
  # accurate default, "file" the quick same-file-only version).
  def self.analyze(sources : Array(Awesome::Source), scope : String = "project") : Array(FileReport)
    collected = sources.map { |source| Collector.new(source) }
    Analyzer.statuses(collected, scope == "file").map do |file|
      FileReport.new(file.source.path, file.source.code_lines, file.statuses)
    end
  end
end

require "./allocations/*"
