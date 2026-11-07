# NameScanner for UncheckedLibPointer — see guards/unchecked_lib_pointer.cr.
# Whether a condition subtree mentions the variable at all.
class Awesome::Guards::UncheckedLibPointer::NameScanner < Crystal::Visitor
  getter? found = false

  def initialize(@name : String)
  end

  def visit(node : Crystal::Var)
    @found = true if node.to_s == @name
    true
  end

  def visit(node : Crystal::InstanceVar)
    @found = true if node.to_s == @name
    true
  end

  def visit(node : Crystal::Assign)
    @found = true if node.target.to_s == @name
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end
end
