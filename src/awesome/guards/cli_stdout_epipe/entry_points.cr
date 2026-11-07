# EntryPoints for CliStdoutEpipe — see guards/cli_stdout_epipe.cr.
#
# Top-level calls of a file: the entry flow (any call except
# `require`) and output calls (the Kernel print family, or any call
# on the STDOUT constant). "Top level" — not inside a def, block,
# proc, class, module, lib or macro: those run on someone else's
# schedule, not the file's.
class Awesome::Guards::CliStdoutEpipe::EntryPoints < Crystal::Visitor
  getter entry_calls = [] of Crystal::Call
  getter output_calls = [] of Crystal::Call

  @depth = 0

  def visit(node : Crystal::Def | Crystal::Block | Crystal::ProcLiteral |
                   Crystal::ClassDef | Crystal::ModuleDef | Crystal::LibDef | Crystal::Macro)
    @depth += 1
    true
  end

  def end_visit(node : Crystal::Def | Crystal::Block | Crystal::ProcLiteral |
                       Crystal::ClassDef | Crystal::ModuleDef | Crystal::LibDef | Crystal::Macro)
    @depth -= 1
  end

  def visit(node : Crystal::Call)
    if @depth.zero?
      entry_calls << node unless node.name == "require"
      output_calls << node if output?(node)
    end
    true
  end

  # Fallback: redefining `visit` in a subclass replaces the base
  # class's overloads, so re-enable traversal for everything else.
  def visit(node : Crystal::ASTNode)
    true
  end

  private def output?(call : Crystal::Call) : Bool
    return call.name.in?(OUTPUT_CALLS) if call.obj.nil?
    obj = call.obj
    obj.is_a?(Crystal::Path) && obj.to_s == "STDOUT"
  end
end
