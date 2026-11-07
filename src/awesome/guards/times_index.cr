# TimesIndex — `xs.size.times { |i| … xs[i] … }` pays for index
# machinery nobody needs.
#
# The idiom re-derives every element through a bounds-checked `[]`
# and drags an index variable through the block, when `xs.each { |x|
# … }` hands over the element itself — no Integer object, no bounds
# check. The guard fires only when the block provably uses the index
# solely to index the very same receiver (`xs[i]` appears and `i` is
# the block argument); anything richer is left alone.
class Awesome::Guards::TimesIndex < Awesome::Guard
  KIND              = "speed"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for `xs.size.times { |i| … xs[i] … }` — every access pays a
    bounds-checked index lookup. `xs.each { |x| }` yields the element
    directly. Fires only when the block's index is used to index the
    same collection and takes nothing else provable into account.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    items.each do |item|
      process item
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    items.size.times do |i|
      process items[i]   # bounds check + index bookkeeping per element
    end
  CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end
end

Awesome::Guard.registered << Awesome::Guards::TimesIndex
