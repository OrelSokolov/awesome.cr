# Visitor for RaiseInLibCallback — see guards/raise_in_lib_callback.cr.
class Awesome::Guards::RaiseInLibCallback::Visitor < Crystal::Visitor
  getter issues = [] of Awesome::Issue

  def initialize(@source : Awesome::Source)
    @libs = Set(String).new # libs declared in this file
    @lib_stack = [] of String
  end

  def visit(node : Crystal::LibDef)
    @libs << node.name.to_s
    @lib_stack.push(node.name.to_s)
    node.body.accept(self)
    @lib_stack.pop
    false
  end

  def visit(node : Crystal::Call)
    # Skip calls inside lib bodies: fun definitions don't use shims.
    return true unless @lib_stack.empty?
    if (obj = node.obj).is_a?(Crystal::Path) && tracks?(obj.names.last)
      node.args.each do |arg|
        check_proc(arg, "#{obj}.#{node.name}") if arg.is_a?(Crystal::ProcLiteral)
      end
    end
    true
  end

  # Fallback: redefining `visit` in a subclass replaces the base
  # class's overloads, so re-enable traversal for everything else.
  def visit(node : Crystal::ASTNode)
    true
  end

  private def check_proc(proc : Crystal::ProcLiteral, call : String) : Nil
    scanner = RaiseScanner.new
    proc.accept(scanner)
    scanner.raises.each do |raise_node|
      @issues << Awesome::Issue.new(
        @source.path,
        "RaiseInLibCallback",
        Awesome::I18n.t("guards.RaiseInLibCallback.main", call: call),
        raise_node.location,
        @source.excerpt_at(raise_node.location.try(&.line_number) || 0)
      )
    end
  end

  # A receiver is a tracked C shim when its lib is declared in this
  # file, or (for libs bound elsewhere, like stdlib's LibC) when it
  # follows the `Lib`-prefix naming convention.
  private def tracks?(name : String) : Bool
    @libs.includes?(name) || name.starts_with?("Lib")
  end
end
