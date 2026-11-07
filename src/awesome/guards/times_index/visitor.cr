# Visitor for TimesIndex — see guards/times_index.cr.
class Awesome::Guards::TimesIndex::Visitor < Crystal::Visitor
  getter issues = [] of Awesome::Issue

  def initialize(@source : Awesome::Source)
  end

  def visit(node : Crystal::Call)
    if node.name == "times" && node.args.empty? &&
       (block = node.block) && (size = node.obj).is_a?(Crystal::Call) &&
       size.name == "size" && size.args.empty? && size.block.nil? &&
       (recv = receiver_name(size.obj)) &&
       block.args.size == 1 && (index = block.args.first).is_a?(Crystal::Var) &&
       indexes_receiver?(block.body, recv, index.name)
      @issues << Awesome::Issue.new(
        @source.path,
        "TimesIndex",
        Awesome::I18n.t("guards.TimesIndex.main", recv: recv, index: index.name),
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

  # Name of a plain receiver: a local (Var), an instance variable, or
  # a bare identifier — the parser renders an undefined local as a
  # 0-arg Call, so `items` and an assigned `items` must both match.
  private def receiver_name(obj : Crystal::ASTNode?) : String?
    case obj
    when Crystal::Var, Crystal::InstanceVar then obj.to_s.lchop('@')
    when Crystal::Call
      obj.name if obj.args.empty? && obj.obj.nil? && obj.block.nil?
    else nil
    end
  end

  # True when the body contains `receiver[index]` for the exact
  # receiver/index pair. Absence is a false negative (fine); presence
  # proves the index exists only to re-fetch elements.
  private def indexes_receiver?(body : Crystal::ASTNode, receiver : String, index : String) : Bool
    scan = IndexScan.new(receiver, index)
    body.accept(scan)
    scan.found?
  end
end
