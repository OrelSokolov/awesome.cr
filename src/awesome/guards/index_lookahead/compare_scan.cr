# CompareScan for IndexLookahead — see guards/index_lookahead.cr.
# Finds a comparison call mentioning the loop variable.
class Awesome::Guards::IndexLookahead::CompareScan < Crystal::Visitor
  COMPARISONS = {"<", "<=", ">", ">=", "==", "!="}

  def initialize(@index : String)
    @found = false
  end

  def found? : Bool
    @found
  end

  def visit(node : Crystal::Call)
    if COMPARISONS.includes?(node.name) && mentions_var?(node)
      @found = true
      return false
    end
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end

  private def mentions_var?(node : Crystal::ASTNode) : Bool
    scan = VarScan.new(@index)
    node.accept(scan)
    scan.found?
  end
end
