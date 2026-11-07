# Collector for HardcodedDependency — see guards/hardcoded_dependency.cr.
# First pass: map ClassDef → names of types nested inside it (any
# depth) — constructing your own nested helpers is not a dependency.
# Second pass: collect `Path.new` calls not covered by the skips.
class Awesome::Guards::HardcodedDependency::Collector < Crystal::Visitor
  getter hardcoded = [] of Hit

  @nested_names = {} of UInt64 => Set(String)
  @classes = [] of Crystal::ClassDef
  @defs = [] of Crystal::Def?

  def initialize(@source : Awesome::Source)
  end

  def run : Array(Hit)
    @source.ast.try &.accept(Nester.new(@nested_names))
    @source.ast.try &.accept(self)
    hardcoded
  end

  def visit(node : Crystal::ClassDef)
    @classes << node
    true
  end

  def end_visit(node : Crystal::ClassDef)
    @classes.pop
  end

  def visit(node : Crystal::Def)
    @defs << node
    true
  end

  def end_visit(node : Crystal::Def)
    @defs.pop
  end

  def visit(node : Crystal::Call)
    collect(node) if node.name == "new" && node.obj.is_a?(Crystal::Path)
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end

  private def collect(node : Crystal::Call) : Nil
    return unless owner = @classes.last? # only inside a class body
    return if owner.struct?              # value types carry data, not collaborators
    path = node.obj.as(Crystal::Path).to_s.lchop("::")
    segment = path.split("::").last
    return if segment.ends_with?("Error") || segment.ends_with?("Exception")
    return if @classes.any? { |c| c.name.to_s.split("::").last == segment } # the class building itself / its own nested helpers
    return if @classes.any? { |c| (@nested_names[c.object_id]? || Set(String).new).includes?(segment) }

    defn = @defs.last?
    return if defn && defn.name == "initialize" # assigning fields in initialize
    return if defn && defn.receiver             # factory class-methods (def self.build)

    where = defn ? "#{owner.name}##{defn.name}" : "#{owner.name} class body"
    hardcoded << Hit.new(path, owner, where, defn, node.location, @source)
  end
end
