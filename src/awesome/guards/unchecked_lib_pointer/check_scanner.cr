# CheckScanner for UncheckedLibPointer — see guards/unchecked_lib_pointer.cr.
# Flags a null check of the variable: an `if`/`unless`/`while`/
# `until` condition mentioning it, or an explicit `.nil?`/`.null?`.
class Awesome::Guards::UncheckedLibPointer::CheckScanner < Crystal::Visitor
  getter? checked = false

  def initialize(@name : String)
  end

  def visit(node : Crystal::If)
    scan_cond(node.cond)
    true
  end

  def visit(node : Crystal::Unless)
    scan_cond(node.cond)
    true
  end

  def visit(node : Crystal::While)
    scan_cond(node.cond)
    true
  end

  def visit(node : Crystal::Until)
    scan_cond(node.cond)
    true
  end

  def visit(node : Crystal::Call)
    if node.name.in?({"nil?", "null?"}) && (obj = node.obj) && obj.to_s == @name
      @checked = true
    end
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end

  private def scan_cond(cond : Crystal::ASTNode) : Nil
    scanner = NameScanner.new(@name)
    cond.accept(scanner)
    @checked = true if scanner.found?
  end
end
