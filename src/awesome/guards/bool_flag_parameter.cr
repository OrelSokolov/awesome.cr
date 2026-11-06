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
  KIND = "smell"
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
        "#{possessive(param.method_name)} #{param.param_name} is a flag argument — " \
        "called with both true and false, two behaviours behind one name; " \
        "two methods (like #{param.method_name} / #{param.method_name}!) " \
        "say it without the branch",
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

  # Cross-file evidence: Bool-restricted parameters of named defs,
  # def-name counts (for the ambiguity skip), and literal Bool
  # arguments at call sites — positional keyed by index, named by
  # parameter name, both keyed by method name.
  class Evidence
    getter bool_params = [] of BoolParam
    @def_counts = Hash(String, Int32).new(0)
    @positional = {} of String => Array({Int32, Bool})
    @named = {} of String => Array({String, Bool})

    def defs_named(method_name : String) : Int32
      @def_counts[method_name]
    end

    def literals_for(method_name : String, index : Int32, param_name : String) : Set(Bool)
      seen = Set(Bool).new
      @positional[method_name]?.try &.each { |(i, v)| seen << v if i == index }
      @named[method_name]?.try &.each { |(n, v)| seen << v if n == param_name }
      seen
    end

    def add_def(method_name : String) : Nil
      @def_counts[method_name] += 1
    end

    def add_bool_param(param : BoolParam) : Nil
      @bool_params << param
    end

    def add_positional(method_name : String, index : Int32, value : Bool) : Nil
      (@positional[method_name] ||= [] of {Int32, Bool}) << {index, value}
    end

    def add_named(method_name : String, param_name : String, value : Bool) : Nil
      (@named[method_name] ||= [] of {String, Bool}) << {param_name, value}
    end
  end

  # One visitor per source, appending into the shared Evidence: def
  # params and call-site literals land in the same tables whatever
  # file they come from.
  private class Visitor < Crystal::Visitor
    def initialize(@path : String, @evidence : Evidence)
    end

    def visit(node : Crystal::Def)
      @evidence.add_def(node.name)
      return true if node.receiver || node.name == "initialize" || operator?(node.name)

      node.args.each_with_index do |arg, index|
        next unless bool_restricted?(arg)
        @evidence.add_bool_param(BoolParam.new(@path, node.name, arg.name, index, node.location))
      end
      true
    end

    def visit(node : Crystal::Call)
      node.args.each_with_index do |arg, index|
        if arg.is_a?(Crystal::BoolLiteral)
          @evidence.add_positional(node.name, index, arg.value)
        end
      end
      node.named_args.try &.each do |named|
        if value = named.value.as?(Crystal::BoolLiteral)
          @evidence.add_named(node.name, named.name, value.value)
        end
      end
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end

    private def bool_restricted?(arg : Crystal::Arg) : Bool
      restriction = arg.restriction
      restriction.is_a?(Crystal::Path) && restriction.to_s == "Bool"
    end

    private def operator?(name : String) : Bool
      !name.matches?(/\A[a-z_]\w*[?!]?\z/)
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::BoolFlagParameter
