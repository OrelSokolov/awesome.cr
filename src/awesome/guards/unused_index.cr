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
  KIND              = "speed"
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
end

Awesome::Guard.registered << Awesome::Guards::UnusedIndex
