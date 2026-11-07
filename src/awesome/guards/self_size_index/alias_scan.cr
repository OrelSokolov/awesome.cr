# AliasScan for SelfSizeIndex — see guards/self_size_index.cr.
# Finds `recv[name]` for one still-tracked size alias, anywhere in
# a statement subtree.
class Awesome::Guards::SelfSizeIndex::AliasScan < Crystal::Visitor
  def initialize(@visitor : Visitor, @name : String, @recv : String,
                 @line : Int32)
  end

  def visit(node : Crystal::Call)
    if node.name == "[]" && node.args.size == 1 &&
       (arg = node.args.first).is_a?(Crystal::Var | Crystal::InstanceVar) &&
       arg.to_s == @name && plain_receiver(node) == @recv
      @visitor.add_issue(node, @name, @line)
    end
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end

  private def plain_receiver(node : Crystal::Call) : String?
    case obj = node.obj
    when Crystal::Var, Crystal::InstanceVar then obj.to_s
    when Crystal::Call
      obj.name if obj.args.empty? && obj.obj.nil? && obj.block.nil?
    else nil
    end
  end
end
