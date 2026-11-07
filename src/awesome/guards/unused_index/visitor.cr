# Visitor for UnusedIndex — see guards/unused_index.cr.
class Awesome::Guards::UnusedIndex::Visitor < Crystal::Visitor
  getter issues = [] of Awesome::Issue

  def initialize(@source : Awesome::Source)
  end

  def visit(node : Crystal::Call)
    if node.name == "each_with_index" && (block = node.block) &&
       block.args.size == 2
      index = block.args[1]
      unless index.name.empty? || index.name.starts_with?('_') ||
             UsesVar.new(index.name).used?(block.body)
        @issues << Awesome::Issue.new(
          @source.path,
          "UnusedIndex",
          Awesome::I18n.t("guards.UnusedIndex.main", index: index.name),
          node.location,
          @source.excerpt_at(node.location.try(&.line_number) || 0)
        )
      end
    end
    true
  end

  # Fallback: redefining `visit` in a subclass replaces the base
  # class's overloads, so re-enable traversal for everything else.
  def visit(node : Crystal::ASTNode)
    true
  end
end
