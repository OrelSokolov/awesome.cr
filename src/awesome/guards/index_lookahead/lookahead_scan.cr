# LookaheadScan for IndexLookahead — see guards/index_lookahead.cr.
# Finds `recv[i + k]` (k ≥ 1) inside one bounded loop body.
class Awesome::Guards::IndexLookahead::LookaheadScan < Crystal::Visitor
  def initialize(@visitor : Visitor, @receiver : String, @index : String)
  end

  def visit(node : Crystal::Call)
    if node.name == "[]" && node.args.size == 1 &&
       (obj = node.obj) && obj.to_s == @receiver &&
       (offset = lookahead_offset(node.args.first))
      @visitor.add_issue(node, @receiver, @index, offset)
    end
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end

  # `i + k` with the bare loop variable and a literal k ≥ 1; nil
  # for bare `i`, `i - 1` or anything not provably past the end.
  private def lookahead_offset(arg : Crystal::ASTNode) : Int32?
    return nil unless arg.is_a?(Crystal::Call) && arg.name == "+" &&
                      arg.args.size == 1 && (obj = arg.obj).is_a?(Crystal::Var) &&
                      obj.name == @index
    case lit = arg.args.first
    when Crystal::NumberLiteral then lit.value.to_i?.try { |k| k >= 1 ? k : nil }
    else                             nil
    end
  end
end
