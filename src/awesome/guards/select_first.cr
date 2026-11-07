# SelectFirst — the whole filtered Array built to take one element.
#
# `xs.select { |x| ok?(x) }.first` runs the predicate over every
# element and allocates the full result Array, then keeps a single
# value. `xs.find { |x| ok?(x) }` stops at the first match — the
# predicate runs only as far as needed and nothing is allocated
# (`find?` is the nilable twin of `first?`).
class Awesome::Guards::SelectFirst < Awesome::Guard
  KIND = "speed"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for `xs.select { … }.first` and `.first?`. The select builds
    the entire filtered Array just to hand back one element; `xs.find
    { … }` returns the first match directly and stops scanning there
    (`find?` for the nilable form).
  TEXT

  GOOD_EXAMPLE = <<-CODE
    first_bad = results.find { |r| r.error? }
  CODE

  BAD_EXAMPLE = <<-CODE
    first_bad = results.select { |r| r.error? }.first
    #           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ every element filtered,
    #           an Array allocated, one value kept
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
      if node.name.in?({"first", "first?"}) && node.args.empty? && node.block.nil? &&
         (obj = node.obj).is_a?(Crystal::Call) && obj.name == "select" &&
         !obj.block.nil? && obj.args.empty?
        replacement = node.name == "first" ? "find { … }" : "find? { … }"
        @issues << Awesome::Issue.new(
          @source.path,
          "SelectFirst",
          Awesome::I18n.t("guards.SelectFirst.main", name: node.name, replacement: replacement),
          node.location,
          @source.excerpt_at(node.location.try(&.line_number) || 0)
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
end

Awesome::Guard.registered << Awesome::Guards::SelectFirst
