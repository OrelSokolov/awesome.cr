# AssignScanner for UncheckedLibPointer — see guards/unchecked_lib_pointer.cr.
# Flags any assignment (`=`, op-assign, multi-assign) to a given
# local/ivar name, anywhere in a subtree.
class Awesome::Guards::UncheckedLibPointer::AssignScanner < Crystal::Visitor
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
    case target
    when Crystal::Var, Crystal::InstanceVar
      @found = true if target.to_s == @name
    end
  end
end
