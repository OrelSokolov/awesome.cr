# LengthScanner for SliceAsCString — see guards/slice_as_c_string.cr.
class Awesome::Guards::SliceAsCString::LengthScanner < Crystal::Visitor
  getter? found = false

  def initialize(@length_names : Array(String))
  end

  def visit(node : Crystal::Call)
    @found = true if @length_names.includes?(node.name)
    true
  end

  def visit(node : Crystal::Var | Crystal::InstanceVar)
    @found = true if @length_names.includes?(node.to_s)
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end
end
