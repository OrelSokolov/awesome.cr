# LogEagerInterp — an eager String built for a log call that may never
# log it.
#
# `log.info "x=#{x}"` interpolates before the call happens, so the
# String is allocated even when the info level is disabled in
# production. The block form is lazy by contract: `log.info { "x=#{x}"
# }` runs the interpolation only if the level is actually emitted.
# Fires only on receivers named `log`/`logger` (`@log` included) — for
# anything else the block form's meaning is not ours to promise.
class Awesome::Guards::LogEagerInterp < Awesome::Guard
  KIND = "memory"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for `log.info "x=\#{x}"` — the interpolation runs before the
    call, so the String is allocated even when the level is disabled.
    The block form `log.info { "x=\#{x}" }` interpolates only when the
    message is actually emitted. Applies to log/logger receivers at
    any log level (trace, debug, info, notice, warn, error, fatal).
  TEXT

  GOOD_EXAMPLE = <<-CODE
    log.info { "x=\#{x}" }   # lazy: built only if emitted
  CODE

  BAD_EXAMPLE = <<-CODE
    log.info "x=\#{x}"       # eager: allocated even when muted
  CODE

  LEVELS = {"trace", "debug", "info", "notice", "warn", "error", "fatal"}

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    def initialize(@source : Awesome::Source)
    end

    def visit(node : Crystal::Call)
      if node.name.in?(LEVELS) && node.block.nil? &&
         (receiver = receiver_name(node.obj)).in?({"log", "logger"}) &&
         node.args.first?.is_a?(Crystal::StringInterpolation)
        @issues << Awesome::Issue.new(
          @source.path,
          "LogEagerInterp",
          "#{receiver}.#{node.name} \"…\" builds the String even when the level is " \
          "disabled; the block form #{receiver}.#{node.name} { \"…\" } interpolates " \
          "only on emit",
          node.location,
          @source.excerpt_at(node.location.try(&.line_number) || 0)
        )
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    # Name of a plain receiver: a local (Var), an instance variable, or
    # a bare identifier — the parser renders an undefined local as a
    # 0-arg Call, so `log` and an assigned `log` must both match.
    private def receiver_name(obj : Crystal::ASTNode?) : String?
      case obj
      when Crystal::Var, Crystal::InstanceVar then obj.to_s.lchop('@')
      when Crystal::Call
        obj.name if obj.args.empty? && obj.obj.nil? && obj.block.nil?
      else nil
      end
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::LogEagerInterp
