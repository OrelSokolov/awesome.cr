# Visitor for ToUnsafeEscape — see guards/to_unsafe_escape.cr.
class Awesome::Guards::ToUnsafeEscape::Visitor < Crystal::Visitor
  getter issues = [] of Awesome::Issue

  @kept = Set(String).new

  def initialize(@source : Awesome::Source)
    if (ast = @source.ast)
      scanner = KeeperScanner.new
      ast.accept(scanner)
      @kept = scanner.kept
    end
  end

  def visit(node : Crystal::Assign)
    if (target = node.target).is_a?(Crystal::InstanceVar | Crystal::ClassVar |
                                    Crystal::Path) &&
       (value = node.value) && (call = to_unsafe_call(value)) && !kept?(call)
      report(value,
        Awesome::I18n.t("guards.ToUnsafeEscape.main", target: target))
    end
    true
  end

  def visit(node : Crystal::Return)
    if (exp = node.exp) && (call = to_unsafe_call(exp)) && !kept?(call)
      report(exp,
        Awesome::I18n.t("guards.ToUnsafeEscape.return"))
    end
    true
  end

  # Fallback: redefining `visit` in a subclass replaces the base
  # class's overloads, so re-enable traversal for everything else.
  def visit(node : Crystal::ASTNode)
    true
  end

  private def to_unsafe_call(node : Crystal::ASTNode) : Crystal::Call?
    return nil unless node.is_a?(Crystal::Call) && node.name == "to_unsafe" && node.args.empty?
    node
  end

  # The receiver of a to_unsafe call whose owner is stored alive
  # somewhere (`@keep = @blob` next to `@raw = @blob.to_unsafe`).
  private def kept?(to_unsafe : Crystal::Call) : Bool
    (obj = to_unsafe.obj).is_a?(Crystal::Var | Crystal::InstanceVar) &&
      @kept.includes?(obj.to_s)
  end

  private def report(node : Crystal::ASTNode, message : String) : Nil
    @issues << Awesome::Issue.new(
      @source.path,
      "ToUnsafeEscape",
      message,
      node.location,
      @source.excerpt_at(node.location.try(&.line_number) || 0)
    )
  end
end
