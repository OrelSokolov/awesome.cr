# IndexLookahead — `xs.size.times { |i| … xs[i + 1] … }` runs one
# past the end on the last iteration.
#
# Neighbor access is the pattern (compare/swap with the next element),
# and the bug is always the same: the loop is bounded by `xs.size` —
# last `i` is `xs.size - 1` — while the body reads `xs[i + k]` with
# `k ≥ 1`, which is index `xs.size` at most one line before the raise.
#
# The provable shape: the bound is a bare `xs.size` (a `times` call or
# an exclusive `0...xs.size` range — an adjusted `xs.size - 1` end is
# the safe form and skipped), and the body indexes that same receiver
# with `i + k`. Any comparison mentioning the loop variable anywhere
# in the body suppresses the issue: the author is already guarding
# the boundary, and a false negative beats a false positive.
class Awesome::Guards::IndexLookahead < Awesome::Guard
  LEVEL    = "vibecoder" # crashes on first run, not a style nit
  SEVERITY = "bug"       # runtime-breaker: IndexError on the last iteration

  SHORT_DESCRIPTION = <<-TEXT
    Checks for lookahead indexing past the end of the loop's own
    collection: `xs.size.times { |i| … xs[i + 1] … }` (or
    `(0...xs.size).each`) — the last `i` is `xs.size - 1`, so `xs[i + 1]`
    is out of bounds. Guard the last iteration (`next if i + 1 ==
    xs.size`) or loop over `0...xs.size - 1`. Any comparison on the
    index in the body already counts as a guard and is skipped.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    items.each_with_index do |item, i|
      process items[i + 1] if i + 1 < items.size
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    items.size.times do |i|
      process items[i + 1]   # IndexError on the last iteration
    end
  CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end
end

Awesome::Guard.registered << Awesome::Guards::IndexLookahead
