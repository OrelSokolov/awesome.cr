# MapFlatten — `map { … }.flatten` walks the collection twice and
# allocates the intermediate Array just to throw it away.
#
# clippy's `map_flatten`: `iter.map(f).flatten()` should be
# `iter.flat_map(f)`. Crystal is the same — `flat_map` yields the
# block's results one by one straight into the output Array: one pass,
# no intermediate allocation.
class Awesome::Guards::MapFlatten < Awesome::Guard
  SHORT_DESCRIPTION = <<-TEXT
    Checks for `xs.map { … }.flatten` — the map allocates an
    intermediate Array that flatten immediately discards. `flat_map`
    builds the result in a single pass with no intermediate allocation
    (clippy's map_flatten, Crystal edition).
  TEXT

  GOOD_EXAMPLE = <<-CODE
    words = lines.flat_map(&.split)   # one pass
  CODE

  BAD_EXAMPLE = <<-CODE
    words = lines.map(&.split).flatten
    #            ^^^^^^^^^^^ intermediate Array
    #                        allocated, then dropped
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
      if node.name == "flatten" && node.args.empty? && node.block.nil? &&
         (obj = node.obj).is_a?(Crystal::Call) && obj.name == "map" &&
         !obj.block.nil?
        @issues << Awesome::Issue.new(
          @source.path,
          "MapFlatten",
          "map { … }.flatten allocates an intermediate Array; flat_map builds " \
          "the result in one pass",
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

Awesome::Guard.registered << Awesome::Guards::MapFlatten
