# SelfSortReassign — `xs = xs.sort` pays for a copy nobody needs.
#
# clippy's `redundant_clone` family: reassigning a collection to the
# result of its own non-mutating method throws away the original and
# keeps a fresh copy. The bang versions (`sort!`, `uniq!`, ...) do the
# same job in place with no allocation — the Crystal take on Rust's
# `vec.sort()` / `sort_unstable()`.
#
# Advisory: the bang version mutates the original object, so it is only
# safe when nothing else holds a reference to it — the message says so.
class Awesome::Guards::SelfSortReassign < Awesome::Guard
  SHORT_DESCRIPTION = <<-TEXT
    Checks for reassignments like `xs = xs.sort` (also uniq, reverse,
    shuffle, rotate). The non-bang method allocates a copy and the
    original is thrown away; the bang version (`xs.sort!`) does the
    same job in place with no allocation. Advisory: the bang version
    mutates the original object, so only apply it when nothing else
    references xs. A comparator block is fine — `sort! { … }` exists
    too.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    items.sort!           # in place, no copy
    items.sort! { |a, b| a.qty <=> b.qty }
  CODE

  BAD_EXAMPLE = <<-CODE
    items = items.sort    # allocates a sorted copy,
                          # then drops the original
  CODE

  # Non-mutating methods whose bang counterpart is equivalent in place.
  BANGABLE = {"sort", "uniq", "reverse", "shuffle", "rotate"}

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    def initialize(@source : Awesome::Source)
    end

    def visit(node : Crystal::Assign)
      if (call = node.value).is_a?(Crystal::Call) &&
         node.target.is_a?(Crystal::Var) &&
         call.obj.is_a?(Crystal::Var) &&
         call.obj.to_s == node.target.to_s &&
         BANGABLE.includes?(call.name) &&
         call.args.empty?
        @issues << Awesome::Issue.new(
          @source.path,
          "SelfSortReassign",
          "Reassigning '#{node.target}' to its own ##{call.name} result pays for " \
          "a copy nobody needs; use ##{call.name}! in place — safe as long as " \
          "nothing else references '#{node.target}'",
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

Awesome::Guard.registered << Awesome::Guards::SelfSortReassign
