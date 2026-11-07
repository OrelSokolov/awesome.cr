# LifecycleScanner for StoredLibPointer — see guards/stored_lib_pointer.cr.
# A `finalize`/`close` def anywhere in the file: the project manages
# C lifetimes explicitly — generous, file-granular suppression.
class Awesome::Guards::StoredLibPointer::LifecycleScanner < Crystal::Visitor
  getter? manages = false

  def visit(node : Crystal::Def)
    @manages = true if node.name.in?({"finalize", "close"})
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end
end
