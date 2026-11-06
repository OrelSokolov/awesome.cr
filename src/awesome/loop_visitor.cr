# A Crystal::Visitor base that tracks whether the current node sits
# inside a loop: `while`/`until` plus the common iterator methods that
# take a block (`times`, `each`, `map`, ...).
#
# Guards that only fire in loop context subclass it, check `loop?` in
# their own visit methods, and delegate everything else to the parent:
#
#   private class Visitor < Awesome::LoopVisitor
#     def visit(node : Crystal::OpAssign)
#       add_issue(node) if loop? && ...
#       true
#     end
#
#     def visit(node : Crystal::ASTNode)
#       super   # keeps loop tracking alive for While/Call/...
#     end
#   end
#
# Loop detection is intentionally broad: a rare iterator that is missed
# only means a false negative — the guard never fires outside a loop.
class Awesome::LoopVisitor < Crystal::Visitor
  # Call-with-block methods that run their block zero or more times.
  ITERATORS = {"times", "each", "each_with_index", "map", "loop",
               "upto", "downto", "step"}

  @loop_depth = 0

  def loop? : Bool
    @loop_depth > 0
  end

  def visit(node : Crystal::While | Crystal::Until)
    @loop_depth += 1
    true
  end

  def end_visit(node : Crystal::While | Crystal::Until)
    @loop_depth -= 1
  end

  def visit(node : Crystal::Call)
    @loop_depth += 1 if loop_call?(node)
    true
  end

  def end_visit(node : Crystal::Call)
    @loop_depth -= 1 if loop_call?(node)
  end

  def visit(node : Crystal::ASTNode)
    true
  end

  private def loop_call?(node : Crystal::Call) : Bool
    !node.block.nil? && ITERATORS.includes?(node.name)
  end
end
