# AssignScanner for SelfSizeIndex — see guards/self_size_index.cr.
# Flags any assignment to a given local/ivar name in a subtree.
class Awesome::Guards::SelfSizeIndex::AssignScanner < Crystal::Visitor
  getter? found = false

  def initialize(@name : String)
  end

  def visit(node : Crystal::Assign)
    check(node.target)
    true
  end

  def visit(node : Crystal::OpAssign)
    check(node.target)
    true
  end

  def visit(node : Crystal::MultiAssign)
    node.targets.each { |t| check(t) }
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end

  private def check(target : Crystal::ASTNode)
    if target.is_a?(Crystal::Var | Crystal::InstanceVar) &&
       target.to_s == @name
      @found = true
    end
  end
end
