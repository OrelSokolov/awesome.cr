# ToSWithoutIo — a zero-arg `to_s` override nobody calls.
#
# `io << obj`, string interpolation and `puts obj` all funnel through
# `to_s(io : IO)` — the zero-arg `Object#to_s` is just a wrapper that
# calls `to_s(io)` and materializes a String (Crystal 1.21:
# interpolation expands to `String.interpolation`, which writes via
# `to_s(io)`). Overriding the wrapper changes neither the IO path nor
# interpolation: every caller keeps the default representation, and
# whoever calls `obj.to_s` directly pays for a fresh String. Define
# `def to_s(io : IO)` and write into the io instead.
#
# Gated by `check_to_s` (default true) — a separately switchable
# pattern: some codebases deliberately keep a zero-arg to_s as API.
class Awesome::Guards::ToSWithoutIo < Awesome::Guard
  KIND = "memory"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for `def to_s` without arguments. `io << obj`, string
    interpolation and `puts obj` all call `to_s(io : IO)`, so a
    zero-arg to_s override never runs on those paths — and every
    direct caller allocates a String. Define `def to_s(io : IO)` and
    write into the io instead. Switch off with check_to_s: false if
    the zero-arg form is deliberate API.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    def to_s(io : IO)
      io << @name << '#' << @id   # feeds io <<, interpolation, puts
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    def to_s
      "\#{@name} \#{@id}"   # io << obj still prints the default
    end
  CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    return [] of Awesome::Issue unless config.bool("check_to_s", true)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    def initialize(@source : Awesome::Source)
    end

    def visit(node : Crystal::Def)
      if node.name == "to_s" && node.args.empty? && node.block_arg.nil?
        @issues << Awesome::Issue.new(
          @source.path,
          "ToSWithoutIo",
          "def to_s without an IO argument never runs where it matters: io <<, " \
          "interpolation and puts all call to_s(io : IO) — define " \
          "`def to_s(io : IO)` and write into the io instead",
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
  end
end

Awesome::Guard.registered << Awesome::Guards::ToSWithoutIo
