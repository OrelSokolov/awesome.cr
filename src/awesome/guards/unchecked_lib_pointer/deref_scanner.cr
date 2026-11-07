# DerefScanner for UncheckedLibPointer — see guards/unchecked_lib_pointer.cr.
# The stored shape: `.value` on a variable tracked from a lib call
# assignment in the same statement block.
class Awesome::Guards::UncheckedLibPointer::DerefScanner < Crystal::Visitor
  def initialize(@source : Awesome::Source, @libs : Hash(String, Set(String)),
                 @origins : Hash(String, Crystal::Call), @issues : Array(Awesome::Issue))
  end

  def visit(node : Crystal::Call)
    if node.name == "value" && (obj = node.obj).is_a?(Crystal::Var | Crystal::InstanceVar) && (assign = @origins[obj.to_s]?)
      assign_line = assign.location.try(&.line_number) || 0
      @issues << Awesome::Issue.new(
        @source.path,
        "UncheckedLibPointer",
        Awesome::I18n.t("guards.UncheckedLibPointer.stored",
          var: obj, assign: assign, line: assign_line),
        node.location,
        @source.excerpt_at(node.location.try(&.line_number) || 0)
      )
    end
    true
  end

  # Nested scopes have their own variables; their blocks are paired
  # separately (a Def body is its own statement list).
  def visit(node : Crystal::Def)
    false
  end

  def visit(node : Crystal::ClassDef)
    false
  end

  def visit(node : Crystal::ModuleDef)
    false
  end

  def visit(node : Crystal::LibDef)
    false
  end

  def visit(node : Crystal::ASTNode)
    true
  end
end
