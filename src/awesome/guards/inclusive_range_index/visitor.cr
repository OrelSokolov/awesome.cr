# Visitor for InclusiveRangeIndex — see guards/inclusive_range_index.cr.
class Awesome::Guards::InclusiveRangeIndex::Visitor < Crystal::Visitor
  getter issues = [] of Awesome::Issue

  def initialize(@source : Awesome::Source)
  end

  def visit(node : Crystal::Call)
    if (block = node.block) && (index = loop_var(block)) &&
       (recv = bounded_receiver(node)) &&
       indexes_receiver?(block.body, recv, index.name)
      @issues << Awesome::Issue.new(
        @source.path,
        "InclusiveRangeIndex",
        Awesome::I18n.t("guards.InclusiveRangeIndex.main", index: index.name, recv: recv),
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

  # The receiver whose size bounds the loop, when the loop is an
  # inclusive `… xs.size` iteration over it:
  # `(a..xs.size).each` or `k.upto(xs.size)`. Exclusive ranges and
  # adjusted ends (`xs.size - 1`) are the safe forms — nil.
  private def bounded_receiver(node : Crystal::Call) : String?
    case node.name
    when "each"
      return nil unless node.args.empty? && (block = node.block) && block.args.size == 1
      range = case obj = unparen(node.obj)
              when Crystal::RangeLiteral then obj
              else                            return nil
              end
      return nil if range.exclusive?
      size_receiver(range.to)
    when "upto"
      return nil unless node.args.size == 1 && node.obj.is_a?(Crystal::NumberLiteral)
      size_receiver(node.args.first)
    else nil
    end
  end

  # Strip a single-expression paren wrap: `(0..n).each` parses with
  # an Expressions node around the range.
  private def unparen(obj : Crystal::ASTNode?) : Crystal::ASTNode?
    if obj.is_a?(Crystal::Expressions) && obj.expressions.size == 1
      obj.expressions.first
    else
      obj
    end
  end

  private def loop_var(block : Crystal::Block) : Crystal::Var?
    return nil unless block.args.size == 1
    block.args.first.as?(Crystal::Var)
  end

  # Receiver of a bare `xs.size` call; nil for anything else
  # (`xs.size - 1` included — an adjusted end is the safe form).
  private def size_receiver(node : Crystal::ASTNode?) : String?
    return nil unless node.is_a?(Crystal::Call) &&
                      node.name == "size" && node.args.empty? && node.block.nil?
    case obj = node.obj
    when Crystal::Var, Crystal::InstanceVar then obj.to_s
    when Crystal::Call
      obj.name if obj.args.empty? && obj.obj.nil? && obj.block.nil?
    else nil
    end
  end

  # True when the body contains `receiver[i]` with the exact bare
  # loop variable — anything offset (`i - 1`) can't be judged here.
  private def indexes_receiver?(body : Crystal::ASTNode, receiver : String, index : String) : Bool
    scan = IndexScan.new(receiver, index)
    body.accept(scan)
    scan.found?
  end
end
