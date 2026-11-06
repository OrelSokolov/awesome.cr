# Base class for all guards. A guard inspects parsed sources and
# reports issues — awesome's equivalent of a rubocop cop.
#
# Every guard carries its own documentation with it (single source of
# truth), shown by `awesome doc` and mirrored in docs/guards/:
#
#   class Awesome::Guards::MyGuard < Awesome::Guard
  #     KIND              = "speed" # or "memory", "code"
#     LEVEL             = "senior" # or "vibecoder", "psycho"
#     SEVERITY          = "warning" # or "bug", "style"
#     SHORT_DESCRIPTION = "..."
#     GOOD_EXAMPLE      = "..."
#     BAD_EXAMPLE       = "..."
#   end
abstract class Awesome::Guard
  @@registered = [] of Guard.class

  # Guards register themselves at file top level (see guards/*.cr):
  #   Awesome::Guard.registered << MyGuard
  # — top-level code reliably runs at startup, unlike class-body calls.
  def self.registered : Array(Guard.class)
    @@registered
  end

  def self.all : Array(Guard.class)
    @@registered
  end

  def name : String
    {{ @type.name.id.stringify.split("::").last }}
  end

  def self.name : String
    {{ @type.name.id.stringify.split("::").last }}
  end

  # The kind of problem a guard looks for — "speed", "memory" or
  # "code". Selects the guard set for `awesome speed` /
  # `awesome memory` / `awesome code`; "all" (the fallback for guards
  # without a KIND) always runs.
  def self.kind : String
    {{ @type.constant(:KIND) || "all" }}
  end

  # Check levels, from lowest to highest. A run at level N executes
  # every guard whose level is N or lower.
  LEVELS        = {"vibecoder", "senior", "psycho"}
  DEFAULT_LEVEL = "senior"

  # How much a guard asks of the code (orthogonal to KIND). Levels pick
  # the audience — choose by how long the code is going to live:
  #
  #   vibecoder — features first: startups validating a hypothesis,
  #               throwaway code; the bar is "don't break on first run"
  #               (leaked/double-freed C memory)
  #   senior    — long-life code: maintainability pays off; best
  #               practices whose fix does NOT hurt readability
  #               (the default: on out of the box)
  #   psycho    — experiments only (hot paths, allocation budgets) or
  #               projects where the normal rules are unviable: trades
  #               readability for a small win (`io << "a=" << a` instead
  #               of puts "a=#{a}"); opt-in via --level psycho or
  #               `level: psycho`
  def self.level : String
    lvl = {{ @type.constant(:LEVEL) || "senior" }}
    LEVELS.includes?(lvl) ? lvl : "senior"
  end

  def self.level_index : Int32
    LEVELS.index(level) || LEVELS.index(DEFAULT_LEVEL).not_nil!
  end

  # Severities, from most to least serious. They pick the color of the
  # report line: red for bugs, yellow for warnings, magenta for style.
  SEVERITIES       = {"bug", "warning", "style"}
  DEFAULT_SEVERITY = "warning"

  # How serious a finding is — orthogonal to LEVEL (how much a guard
  # asks of the code) and to KIND (which command runs it):
  #
  #   bug     — the code is broken at runtime: leaked or double-freed
  #             C memory, undefined behaviour
  #   warning — a real problem worth fixing: wasted allocations,
  #             O(n) traps, eager work
  #   style   — design/idiom nits (smells): the code works, it just
  #             reads worse
  #
  # Defaults by kind: code guards are style, everything else is a
  # warning; runtime-breakers set SEVERITY = "bug" explicitly.
  def self.severity : String
    sev = {{ @type.constant(:SEVERITY) }} || (kind == "code" ? "style" : DEFAULT_SEVERITY)
    SEVERITIES.includes?(sev) ? sev : DEFAULT_SEVERITY
  end

  def self.short_description : String
    {{ @type.constant(:SHORT_DESCRIPTION) || "" }}
  end

  def self.good_example : String
    {{ @type.constant(:GOOD_EXAMPLE) || "" }}
  end

  def self.bad_example : String
    {{ @type.constant(:BAD_EXAMPLE) || "" }}
  end

  # Per-file check. The base implementation reports nothing; guards that
  # inspect single files override it (all existing guards do).
  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    [] of Awesome::Issue
  end

  # Per-project check: called once with every collected source, after
  # the per-file pass — for guards whose evidence spans files (type
  # hierarchies, cross-file references). Issues are still attached to a
  # concrete file:line, so `Report` is unchanged. The base implementation
  # reports nothing; per-project guards build an `Awesome::Index` from
  # the sources and override only this method.
  def test_project(sources : Array(Awesome::Source), config : Awesome::GuardConfig) : Array(Awesome::Issue)
    [] of Awesome::Issue
  end
end
