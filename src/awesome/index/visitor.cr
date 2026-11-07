# Walks one source for Awesome::Index, registering a TypeEntry per
# ClassDef/ModuleDef with the file's naming stack as its qualified
# name, and attaching def names (regular and `abstract def`) to the
# innermost type.
class Awesome::Index::Visitor < Crystal::Visitor
  @nesting = [] of TypeEntry # innermost type last

  def initialize(@index : Index, @path : String)
  end

  def visit(node : Crystal::ClassDef)
    push(node, superclass_of(node))
    true
  end

  def visit(node : Crystal::ModuleDef)
    push(node, nil)
    true
  end

  def visit(node : Crystal::Include)
    @nesting.last?.try { |entry| entry.included_modules << node.name.to_s }
    true
  end

  def end_visit(node : Crystal::ClassDef | Crystal::ModuleDef)
    @nesting.pop
  end

  def visit(node : Crystal::Def)
    if entry = @nesting.last?
      entry.def_names << node.name
      entry.abstract_def_names << node.name if node.abstract?
    end
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end

  private def push(node : Crystal::ClassDef | Crystal::ModuleDef,
                   superclass : String?) : Nil
    names = @nesting.map(&.qualified_name) << node.name.to_s
    entry = TypeEntry.new(names.join("::"), superclass, node,
      [] of String, [] of String, [] of String,
      TypeEntry::Origin.new(@path, node.location))
    # add() folds a reopening into the canonical entry and hands it
    # back — defs written in this reopening attach to that one.
    @nesting << @index.add(entry)
  end

  # Superclass path as a plain string: `Base(T)` keeps only `Base` —
  # type vars never matter for hierarchy checks.
  private def superclass_of(node : Crystal::ClassDef) : String?
    case parent = node.superclass
    when Crystal::Generic then parent.name.to_s.lchop("::")
    when Crystal::Path    then parent.to_s.lchop("::")
    else                       parent.try &.to_s
    end
  end
end
