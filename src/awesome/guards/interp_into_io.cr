# InterpIntoIo — interpolation fed straight into an IO call.
#
# `io << "a#{b}c"` expands to `io << String.interpolation("a", b, "c")`:
# the interpolated String is fully allocated before the `<<` even runs
# (verified on Crystal 1.21 — literal_expander.cr). Appending the parts
# separately (`io << "a" << b << "c"`) lets each `to_s(io)` write
# directly into the IO: zero intermediate Strings.
#
# For `<<` the guard fires only on IO-ish receiver names (`io`,
# `stdout`, `..._io`, ...) — on an unknown receiver (an Array, say) the
# append-the-parts fix would not apply, and a false negative beats a
# false positive. `puts`/`print` (and `io.puts`/`io.print`) have IO
# semantics by definition, so they always fire.
class Awesome::Guards::InterpIntoIo < Awesome::Guard
  KIND = "memory"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for string interpolation inside IO calls — `io << "a\#{b}c"`,
    `puts "x=\#{x}"`, `io.print "v=\#{v}"`. The interpolation expands to
    String.interpolation and allocates the whole String before the call;
    appending the parts separately (io << "a" << b) writes each piece
    straight into the IO with zero intermediate Strings.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    io << "user=" << user.name << " id=" << user.id
    # each to_s(io) writes into io directly
  CODE

  BAD_EXAMPLE = <<-CODE
    io << "user=\#{user.name} id=\#{user.id}"
    # String.interpolation allocates the full String first
  CODE

  # Receiver names that are provably IO-ish for the `<<` form.
  IO_NAMES = {"io", "stdout", "stderr", "out", "output", "buffer",
              "writer", "stream", "socket"}

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
      case node.name
      when "puts", "print"
        fire(node) if node.args.any?(&.is_a?(Crystal::StringInterpolation))
      when "<<"
        fire(node) if node.args.size == 1 &&
                      node.args.first.is_a?(Crystal::StringInterpolation) &&
                      io_receiver?(node)
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    private def io_receiver?(node : Crystal::Call) : Bool
      name = receiver_name(node.obj)
      return false unless name
      IO_NAMES.includes?(name) || name.ends_with?("_io") || name.starts_with?("io_")
    end

    # Name of a plain receiver: a local (Var), an instance variable, or
    # a bare identifier — the parser renders an undefined local as a
    # 0-arg Call, so `io` and an assigned `io` must both match.
    private def receiver_name(obj : Crystal::ASTNode?) : String?
      case obj
      when Crystal::Var, Crystal::InstanceVar then obj.to_s.lchop('@')
      when Crystal::Call
        obj.name if obj.args.empty? && obj.obj.nil? && obj.block.nil?
      else nil
      end
    end

    private def fire(node : Crystal::Call)
      @issues << Awesome::Issue.new(
        @source.path,
        "InterpIntoIo",
        "Interpolation inside #{node.name} allocates the whole String first " \
        "(String.interpolation); append the parts instead — io << \"a=\" << a",
        node.location,
        @source.excerpt_at(node.location.try(&.line_number) || 0)
      )
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::InterpIntoIo
