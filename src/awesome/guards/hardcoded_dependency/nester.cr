# Nester for HardcodedDependency — see guards/hardcoded_dependency.cr.
# Collects the names of types defined inside each ClassDef, for
# every enclosing level (a type nested two levels deep is visible to
# both ancestors). Type-defining nodes only — ClassDef/ModuleDef,
# `record` macro calls, aliases and enums.
class Awesome::Guards::HardcodedDependency::Nester < Crystal::Visitor
  @stack = [] of Crystal::ClassDef

  def initialize(@nested_names : Hash(UInt64, Set(String)))
  end

  def visit(node : Crystal::ClassDef | Crystal::ModuleDef)
    register(node.name.to_s)
    if node.is_a?(Crystal::ClassDef)
      @stack << node
    end
    true
  end

  def end_visit(node : Crystal::ClassDef)
    @stack.pop
  end

  def visit(node : Crystal::Call)
    register(node.args.first.to_s) if node.name == "record" && node.args.first?
    true
  end

  def visit(node : Crystal::Alias | Crystal::EnumDef)
    register(node.name.to_s)
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end

  private def register(name : String) : Nil
    segment = name.split("::").last
    @stack.each do |outer|
      (@nested_names[outer.object_id] ||= Set(String).new) << segment
    end
  end
end
