# Base class for all guards. A guard inspects parsed sources and
# reports issues — awesome's equivalent of a rubocop cop.
#
# Every guard carries its own documentation with it (single source of
# truth), shown by `awesome doc` and mirrored in docs/guards/:
#
#   class Awesome::Guards::MyGuard < Awesome::Guard
#     KIND              = "speed" # or "memory", "smell"
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
  # "smell". Selects the guard set for `awesome speed` /
  # `awesome memory` / `awesome smell`; "all" (the fallback for guards
  # without a KIND) always runs.
  def self.kind : String
    {{ @type.constant(:KIND) || "all" }}
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
