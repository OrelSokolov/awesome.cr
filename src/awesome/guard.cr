# Base class for all guards. A guard inspects parsed sources and
# reports issues — awesome's equivalent of a rubocop cop.
#
# Every guard carries its own documentation with it (single source of
# truth), shown by `awesome doc` and mirrored in docs/guards/:
#
#   class Awesome::Guards::MyGuard < Awesome::Guard
#     KIND              = "speed" # or "memory"
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

  # The kind of problem a guard looks for — "speed" or "memory".
  # Selects the guard set for `awesome speed` / `awesome memory`;
  # "all" (the fallback for guards without a KIND) always runs.
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

  abstract def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
end
