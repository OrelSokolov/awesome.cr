# Visitor for StoredLibPointer — see guards/stored_lib_pointer.cr.
class Awesome::Guards::StoredLibPointer::Visitor < Crystal::Visitor
  getter issues = [] of Awesome::Issue

  @libs = Set(String).new # libs declared in this file
  @lib_stack = [] of String
  @manages_lifecycle = false

  def initialize(@source : Awesome::Source, @allocators : Array(String))
    if (ast = @source.ast)
      scanner = LifecycleScanner.new
      ast.accept(scanner)
      @manages_lifecycle = scanner.manages?
    end
  end

  def visit(node : Crystal::LibDef)
    @libs << node.name.to_s
    @lib_stack.push(node.name.to_s)
    node.body.accept(self)
    @lib_stack.pop
    false
  end

  def visit(node : Crystal::Assign)
    # Skip assignments inside lib bodies: fun definitions
    # (`fun x = ...`) define the shim, they don't use it.
    if @lib_stack.empty? && !@manages_lifecycle &&
       (target = node.target).is_a?(Crystal::InstanceVar | Crystal::ClassVar |
                                    Crystal::Path) &&
       (value = node.value).is_a?(Crystal::Call) &&
       (obj = value.obj).is_a?(Crystal::Path) &&
       @libs.includes?(obj.names.last) &&
       !@allocators.includes?(value.name)
      @issues << Awesome::Issue.new(
        @source.path,
        "StoredLibPointer",
        Awesome::I18n.t("guards.StoredLibPointer.main",
          target: target, value: value, lib: obj),
        value.location,
        @source.excerpt_at(value.location.try(&.line_number) || 0)
      )
    end
    true
  end

  # Fallback: redefining `visit` in a subclass replaces the base
  # class's overloads, so re-enable traversal for everything else.
  def visit(node : Crystal::ASTNode)
    true
  end
end
