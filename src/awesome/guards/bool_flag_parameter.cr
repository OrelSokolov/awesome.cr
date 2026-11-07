# BoolFlagParameter — two behaviours hiding behind one name.
#
# A Bool parameter that call sites feed with both literal `true` and
# literal `false` is a method doing two jobs, named by its flag: the
# body branches on the parameter and each branch is a behaviour
# callers actually use. Two methods say the same thing without the
# branch — `sync`/`sync!`, `render`/`render_draft` — and keep each
# call site self-describing.
#
# The evidence requirement is what keeps the guard honest: it fires
# only when *both* literals are observed at real call sites in the
# project, not on the parameter's mere existence (plenty of Bool
# params are legitimately one-sided). Project-wide (`test_project`)
# because call sites usually live in other files.
#
# Attribution is syntactic, so same-named methods are skipped: when
# several defs share the name, a literal can't be pinned to one of
# them — better a false negative. `initialize` defs are skipped for
# the same reason (`Foo.new(true)` can't be attributed by name alone),
# as are operator names (`==`, `[]`, ...), and so is a parameter named
# `default` — it carries a value, not a branch (config readers pass
# both literals legitimately).
class Awesome::Guards::BoolFlagParameter < Awesome::Guard
  KIND              = "code"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for Bool parameters that call sites feed with both literal
    true and literal false — a method doing two jobs, named by its
    flag; two methods (sync / sync!) say it without the branch. Fires
    only on observed evidence: both literals must appear at call
    sites in the project. Same-named methods, initialize defs and
    operators are skipped (a literal can't be attributed to them).
  TEXT

  GOOD_EXAMPLE = <<-CODE
    class Sync
      def sync! # destructive — its own name, no flag to read
        rebuild_index
      end

      def sync # safe — same class, two honest methods
        copy_files
      end
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    class Sync
      def run(force : Bool) # one name, two behaviours
        force ? rebuild_index : copy_files
      end
    end

    Sync.new.run(true)  # the branch callers actually take,
    Sync.new.run(false) # spelled out at every call site
  CODE

  # Parameters never treated as flags: a `default` carries a value,
  # not a branch (config readers pass both literals legitimately).
  DEFAULT_SKIPPED = {"default"}

  def test_project(sources : Array(Awesome::Source), config : Awesome::GuardConfig) : Array(Awesome::Issue)
    allowed = config.strings("allowed", [] of String)

    evidence = Evidence.new
    sources.each do |source|
      source.ast.try &.accept(Visitor.new(source.path, evidence))
    end

    by_path = sources.map { |s| {s.path, s} }.to_h

    evidence.bool_params.compact_map do |param|
      # Unattributable: several defs share the name — a literal at a
      # call site can't be pinned to one of them.
      next if evidence.defs_named(param.method_name) > 1
      next if DEFAULT_SKIPPED.includes?(param.param_name) || allowed.includes?(param.param_name)

      seen = evidence.literals_for(param.method_name, param.index, param.param_name)
      next unless seen == Set{true, false}

      source = by_path[param.path]?
      Awesome::Issue.new(
        param.path,
        "BoolFlagParameter",
        Awesome::I18n.t("guards.BoolFlagParameter.main",
          method_possessive: possessive(param.method_name), param: param.param_name,
          method: param.method_name),
        param.location,
        source.try(&.excerpt_at(param.line))
      )
    end
  end

  # sync's force / retries' exhausted — English possessive, s-suffix aware.
  private def possessive(name : String) : String
    name.ends_with?('s') ? "#{name}'" : "#{name}'s"
  end

  record BoolParam, path : String, method_name : String, param_name : String,
    index : Int32, location : Crystal::Location? do
    def line : Int32
      @location.try(&.line_number) || 0
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::BoolFlagParameter
