# UsesVar for UnusedIndex — see guards/unused_index.cr.
# Whether a variable with the given name appears anywhere in an AST.
class Awesome::Guards::UnusedIndex::UsesVar < Crystal::Visitor
  def initialize(@name : String)
    @found = false
  end

  def used?(node : Crystal::ASTNode) : Bool
    node.accept(self)
    @found
  end

  def visit(node : Crystal::Var)
    @found = true if node.name == @name
    false
  end

  # Fallback: redefining `visit` in a subclass replaces the base
  # class's overloads, so re-enable traversal for everything else.
  def visit(node : Crystal::ASTNode)
    true
  end
end
