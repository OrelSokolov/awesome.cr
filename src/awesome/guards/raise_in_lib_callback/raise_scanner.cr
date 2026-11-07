# RaiseScanner for RaiseInLibCallback — see guards/raise_in_lib_callback.cr.
# Collects every `raise`/`reraise` in a subtree. In the parsed AST
# both are plain calls (no dedicated Raise node before semantic
# analysis), so match them by name.
class Awesome::Guards::RaiseInLibCallback::RaiseScanner < Crystal::Visitor
  getter raises = [] of Crystal::Call

  def visit(node : Crystal::Call)
    @raises << node if node.name.in?({"raise", "reraise"})
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end
end
