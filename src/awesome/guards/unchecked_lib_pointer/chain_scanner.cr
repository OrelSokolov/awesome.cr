# ChainScanner for UncheckedLibPointer — see guards/unchecked_lib_pointer.cr.
# The chained shape: `LibFoo.find(x).value` — dereference right on
# the result of a pointer-returning lib call.
class Awesome::Guards::UncheckedLibPointer::ChainScanner < Crystal::Visitor
  def initialize(@source : Awesome::Source, @libs : Hash(String, Set(String)), @issues : Array(Awesome::Issue))
  end

  def visit(node : Crystal::Call)
    if node.name == "value" && (obj = node.obj).is_a?(Crystal::Call) &&
       (receiver = obj.obj).is_a?(Crystal::Path) && qualifies?(receiver.names.last, obj)
      @issues << Awesome::Issue.new(
        @source.path,
        "UncheckedLibPointer",
        Awesome::I18n.t("guards.UncheckedLibPointer.main",
          call: obj, lib: receiver, fun: obj.name),
        node.location,
        @source.excerpt_at(node.location.try(&.line_number) || 0)
      )
    end
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end

  private def qualifies?(lib_name : String, call : Crystal::Call) : Bool
    if funs = @libs[lib_name]?
      funs.includes?(call.name) # declared here: must return T*
    else
      lib_name.starts_with?("Lib") # bound elsewhere: assume a pointer
    end
  end
end
