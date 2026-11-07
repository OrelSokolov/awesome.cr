# IndexScan for InclusiveRangeIndex — see guards/inclusive_range_index.cr.
# Scans the block body for `receiver[index]` with the bare loop variable.
class Awesome::Guards::InclusiveRangeIndex::IndexScan < Crystal::Visitor
  def initialize(@receiver : String, @index : String)
    @found = false
  end

  def found? : Bool
    @found
  end

  def visit(node : Crystal::Call)
    if node.name == "[]" && node.args.size == 1 &&
       (obj = node.obj) && obj.to_s == @receiver &&
       (arg = node.args.first).is_a?(Crystal::Var) && arg.name == @index
      @found = true
    end
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end
end
