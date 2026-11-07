# StringConcatInLoop — repeated string concatenation reallocates every
# iteration.
#
# clippy's `string_add_assign` flags the same pattern in Rust: `s +=
# "…"` inside a loop allocates a fresh String each iteration; the fix is
# `String::with_capacity` + `push_str`. In Crystal the fix is to append
# into an `IO::Memory` (or `String::Builder`) and materialize the String
# once, after the loop.
#
# Loop detection is intentionally broad: `while`/`until` plus the common
# iterator methods with a block (`times`, `each`, `map`, `loop`, ...).
# A rare iterator that is missed only means a false negative — the guard
# never fires outside a loop.
class Awesome::Guards::StringConcatInLoop < Awesome::Guard
  KIND = "speed"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for string concatenation inside loops (`s += "…"` or
    `s = s + "…"`). Each iteration allocates a whole new String; append
    into an IO::Memory (or String::Builder) instead and materialize the
    String once after the loop — Crystal's take on Rust's
    `String::with_capacity` + `push_str`. Only string literals and
    interpolations on the right-hand side are flagged (number += stays
    untouched).
  TEXT

  GOOD_EXAMPLE = <<-CODE
    io = IO::Memory.new
    while line = reader.gets
      io << line          # appends in place, no realloc
    end
    text = io.to_s        # one String for the whole loop
  CODE

  BAD_EXAMPLE = <<-CODE
    text = ""
    while line = reader.gets
      text += line        # fresh String allocation every iteration
    end
  CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  # Loop tracking (while/until + iterator calls with blocks) lives in
  # Awesome::LoopVisitor, shared with the other loop-context guards.
  private class Visitor < Awesome::LoopVisitor
    getter issues = [] of Awesome::Issue

    def initialize(@source : Awesome::Source)
    end

    def visit(node : Crystal::OpAssign)
      if loop? && node.op == "+" &&
         string_value?(node.value) && assignable?(node.target)
        add_issue(node)
      end
      true
    end

    def visit(node : Crystal::Assign)
      if loop? && assignable?(node.target) &&
         (call = node.value).is_a?(Crystal::Call) && call.name == "+" &&
         call.obj.is_a?(Crystal::Var | Crystal::InstanceVar) &&
         call.obj.to_s == node.target.to_s &&
         call.args.any? { |a| string_value?(a) }
        add_issue(node)
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else
    # (keeps LoopVisitor's loop tracking alive).
    def visit(node : Crystal::ASTNode)
      super
    end

    private def assignable?(node : Crystal::ASTNode) : Bool
      node.is_a?(Crystal::Var) || node.is_a?(Crystal::InstanceVar)
    end

    private def string_value?(node : Crystal::ASTNode) : Bool
      node.is_a?(Crystal::StringLiteral) || node.is_a?(Crystal::StringInterpolation)
    end

    private def add_issue(node : Crystal::ASTNode)
      @issues << Awesome::Issue.new(
        @source.path,
        "StringConcatInLoop",
        Awesome::I18n.t("guards.StringConcatInLoop.main"),
        node.location,
        @source.excerpt_at(node.location.try(&.line_number) || 0)
      )
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::StringConcatInLoop
