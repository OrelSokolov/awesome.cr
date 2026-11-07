# MapCompact — two passes and an intermediate Array where one call
# would do.
#
# `xs.map { |x| f(x) }.compact` maps into a fresh Array, then walks it
# again to copy the non-nil values into another one. `xs.compact_map {
# |x| f(x) }` appends each non-nil result straight into the output
# Array: one pass, one allocation. Companion to MapFlatten.
class Awesome::Guards::MapCompact < Awesome::Guard
  KIND = "speed"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for `xs.map { … }.compact` — the map's intermediate Array is
    walked a second time just to drop the nils. `xs.compact_map { … }`
    builds the result in a single pass with one allocation.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    names = users.compact_map { |u| u.email }
  CODE

  BAD_EXAMPLE = <<-CODE
    names = users.map { |u| u.email }.compact
    #            ^^^^^^^^^^^^^^^^^^^ intermediate Array,
    #                                 walked again by compact
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
      if node.name == "compact" && node.args.empty? && node.block.nil? &&
         (obj = node.obj).is_a?(Crystal::Call) && obj.name == "map" &&
         !obj.block.nil?
        @issues << Awesome::Issue.new(
          @source.path,
          "MapCompact",
          Awesome::I18n.t("guards.MapCompact.main"),
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

Awesome::Guard.registered << Awesome::Guards::MapCompact
