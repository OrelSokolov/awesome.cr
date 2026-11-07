# UnusedIndex — `each_with_index` pays for an index nobody reads.
#
# clippy's `unused_enumerate_index`: iterating with an index you never
# use makes readers look for a reason that isn't there, and in Crystal
# `each` also skips the index bookkeeping entirely. If the block's
# second parameter (the index) is never referenced in the body, plain
# `each` does the same job.
#
# Convention-aware: an index named `_` (or `_something`) is treated as
# intentionally unused and not flagged — that's already idiomatic.
class Awesome::Guards::UnusedIndex < Awesome::Guard
  KIND = "speed"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for `each_with_index` blocks whose index parameter is never
    used in the block body — plain `each` does the same job and skips
    the index bookkeeping. A parameter named `_` or starting with `_`
    counts as intentionally unused and is not flagged.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    items.each do |item|
      process item
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    items.each_with_index do |item, i|
      process item     # i never used
    end
  CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  private class Visitor < Crystal::Visitor
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

  # Whether a variable with the given name appears anywhere in an AST.
  private class UsesVar < Crystal::Visitor
    def initialize(@name : String)
      @found = false
    end

    def used?(node : Crystal::ASTNode) : Bool
      node.accept(self)
      @found
    end

    def visit(node : Crystal::Var)
      @found = true if node.name == @name
      false
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::UnusedIndex
