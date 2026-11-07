# Annotations for HardcodedDependency — see guards/hardcoded_dependency.cr.
# Type annotations of one class, as written paths: ivar/class-var
# declarations (`@store : Store`) and parameter restrictions
# (`def f(x : Store)`). Method *return* types are deliberately not
# collected — `def pick : Store; MemoryStore.new; end` is a factory
# choosing an implementation, not a consumer bypassing a seam.
class Awesome::Guards::HardcodedDependency::Annotations < Crystal::Visitor
  getter paths = [] of String

  def initialize(@owner : Crystal::ClassDef)
  end

  def run : Array(String)
    @owner.accept(self)
    paths
  end

  def visit(node : Crystal::TypeDeclaration)
    paths << written(node.declared_type) if restriction?(node.declared_type)
    true
  end

  def visit(node : Crystal::Arg)
    if restriction = node.restriction
      paths << written(restriction) if restriction?(restriction)
    end
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end

  private def restriction?(restriction : Crystal::ASTNode?) : Bool
    restriction.is_a?(Crystal::Path) || restriction.is_a?(Crystal::Generic)
  end

  private def written(restriction : Crystal::ASTNode) : String
    case restriction
    when Crystal::Generic then restriction.name.to_s.lchop("::")
    else                       restriction.to_s.lchop("::")
    end
  end
end
