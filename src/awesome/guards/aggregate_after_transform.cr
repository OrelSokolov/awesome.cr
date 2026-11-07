# AggregateAfterTransform — an intermediate Array built just to be
# aggregated away.
#
# `xs.map { |x| f(x) }.sum` maps the whole collection into a fresh
# Array, then reduces it to a number — the Array is pure garbage.
# `xs.sum { |x| f(x) }` feeds each element straight into the reduction:
# one pass, no allocation. Same for `.size` and `.empty?` on a map —
# the block never changes the element count, so `xs.size` on the
# original answers directly.
class Awesome::Guards::AggregateAfterTransform < Awesome::Guard
  KIND = "speed"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for `xs.map { … }.sum`, `.size` and `.empty?` — the map
    allocates an intermediate Array that the aggregation immediately
    throws away. `xs.sum { … }` reduces in one pass; `xs.size` and
    `xs.empty?` on the original give the same answer because a map
    never changes the element count.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    total = invoices.sum { |inv| inv.amount }
    count = invoices.size
  CODE

  BAD_EXAMPLE = <<-CODE
    total = invoices.map { |inv| inv.amount }.sum
    count = invoices.map { |inv| inv.amount }.size
    #        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ intermediate Array
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
      if node.args.empty? && node.block.nil? &&
         (obj = node.obj).is_a?(Crystal::Call) && obj.name == "map" &&
         !obj.block.nil? && (recv = obj.obj)
        case node.name
        when "sum"
          add_issue(node, "#{recv}.sum { … } with the same block aggregates in one pass")
        when "size"
          add_issue(node, "#{recv}.size is the same number — a map never changes the count")
        when "empty?"
          add_issue(node, "#{recv}.empty? answers directly — a map never changes the count")
        end
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    private def add_issue(node : Crystal::Call, fix : String)
      @issues << Awesome::Issue.new(
        @source.path,
        "AggregateAfterTransform",
        Awesome::I18n.t("guards.AggregateAfterTransform.main", name: node.name, fix: fix),
        node.location,
        @source.excerpt_at(node.location.try(&.line_number) || 0)
      )
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::AggregateAfterTransform
