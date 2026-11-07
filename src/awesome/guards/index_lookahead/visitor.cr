# Visitor for IndexLookahead — see guards/index_lookahead.cr.
class Awesome::Guards::IndexLookahead::Visitor < Crystal::Visitor
  getter issues = [] of Awesome::Issue

  def initialize(@source : Awesome::Source)
  end

  def visit(node : Crystal::Call)
    if (block = node.block) && (index = loop_var(block)) &&
       (recv = bounded_receiver(node)) &&
       !compares_index?(block.body, index.name)
      LookaheadScan.new(self, recv, index.name).tap do |scan|
        block.body.accept(scan)
      end
    end
    true
  end

  # Fallback: redefining `visit` in a subclass replaces the base
  # class's overloads, so re-enable traversal for everything else.
  def visit(node : Crystal::ASTNode)
    true
  end

  private def loop_var(block : Crystal::Block) : Crystal::Var?
    return nil unless block.args.size == 1
    block.args.first.as?(Crystal::Var)
  end

  # The receiver whose bare `xs.size` bounds the loop, meaning the
  # block's last index into it is `xs.size - 1`: a `xs.size.times`
  # call or an exclusive `(… xs.size).each` range. Anything else —
  # plain `n.times`, an inclusive range, an adjusted `xs.size - 1`
  # end — can't prove the bound and returns nil.
  private def bounded_receiver(node : Crystal::Call) : String?
    case node.name
    when "times"
      return nil unless node.args.empty?
      size_receiver(node.obj)
    when "each"
      return nil unless node.args.empty?
      range = case obj = unparen(node.obj)
              when Crystal::RangeLiteral then obj
              else                            return nil
              end
      return nil unless range.exclusive?
      size_receiver(range.to)
    else nil
    end
  end

  # Strip a single-expression paren wrap: `(0...n).each` parses with
  # an Expressions node around the range.
  private def unparen(obj : Crystal::ASTNode?) : Crystal::ASTNode?
    if obj.is_a?(Crystal::Expressions) && obj.expressions.size == 1
      obj.expressions.first
    else
      obj
    end
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

  # Any comparison on the loop variable anywhere in the body — the
  # author is guarding the boundary; stay quiet (false negative,
  # never a false positive).
  private def compares_index?(body : Crystal::ASTNode, index : String) : Bool
    scan = CompareScan.new(index)
    body.accept(scan)
    scan.found?
  end

  # Reached by LookaheadScan: report one offending access site.
  def add_issue(node : Crystal::Call, recv : String, index : String, offset : Int32) : Nil
    Awesome::Issue.new(
      @source.path,
      "IndexLookahead",
      Awesome::I18n.t("guards.IndexLookahead.main",
        recv: recv,
        index: index,
        offset: offset),
      node.location,
      @source.excerpt_at(node.location.try(&.line_number) || 0)
    ).tap { |issue| @issues << issue }
  end
end
