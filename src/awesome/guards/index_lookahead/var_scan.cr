# VarScan for IndexLookahead — see guards/index_lookahead.cr.
# Finds a bare use of a named local variable in a subtree.
class Awesome::Guards::IndexLookahead::VarScan < Crystal::Visitor
  getter? found = false

  def initialize(@index : String)
  end

  def visit(node : Crystal::Var)
    @found = true if node.name == @index
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end
end
