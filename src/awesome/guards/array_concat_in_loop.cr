# ArrayConcatInLoop — growing an Array with `+=` copies it whole on
# every iteration.
#
# `arr += [x]` is `arr = arr + [x]`: a fresh Array with every old
# element copied in, thrown away again on the next pass — quadratic
# total work for what is a single append. `arr << x` appends in place
# (amortized O(1)). Same shape as StringConcatInLoop, one type over.
class Awesome::Guards::ArrayConcatInLoop < Awesome::Guard
  KIND = "speed"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for Array concatenation inside loops (`arr += [x]` or
    `arr = arr + [x]`). Each iteration copies the whole Array into a
    fresh one — O(n²) total. Append in place with `arr << x` instead.
    Only Array literals on the right-hand side are flagged.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    acc = [] of Int32
    items.each do |item|
      acc << item        # append in place, no copy
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    acc = [] of Int32
    items.each do |item|
      acc += [item]      # full copy of acc, every iteration
    end
  CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  private class Visitor < Awesome::LoopVisitor
    getter issues = [] of Awesome::Issue

    def initialize(@source : Awesome::Source)
    end

    def visit(node : Crystal::OpAssign)
      if loop? && node.op == "+" && node.value.is_a?(Crystal::ArrayLiteral) &&
         assignable?(node.target)
        add_issue(node)
      end
      true
    end

    def visit(node : Crystal::Assign)
      if loop? && assignable?(node.target) &&
         (call = node.value).is_a?(Crystal::Call) && call.name == "+" &&
         call.obj.is_a?(Crystal::Var | Crystal::InstanceVar) &&
         call.obj.to_s == node.target.to_s &&
         call.args.any?(&.is_a?(Crystal::ArrayLiteral))
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

    private def add_issue(node : Crystal::ASTNode)
      @issues << Awesome::Issue.new(
        @source.path,
        "ArrayConcatInLoop",
        "Array += inside a loop copies the whole Array every iteration " \
        "(O(n²) total); append in place with << instead",
        node.location,
        @source.excerpt_at(node.location.try(&.line_number) || 0)
      )
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::ArrayConcatInLoop
