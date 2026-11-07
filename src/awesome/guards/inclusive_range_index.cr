# InclusiveRangeIndex — `(0..xs.size).each { |i| xs[i] }` reaches
# index `xs.size` on the last pass.
#
# The inclusive `..` range runs its last iteration with
# `i == xs.size`, and `xs[i]` raises IndexError right there. The
# provable shape: the range (or `upto`) ends at a bare `xs.size`, and
# the block indexes that same receiver with the bare loop variable —
# `xs[i - 1]` or any offset is left alone, as are the safe exclusive
# forms (`...`, `times`, `0...xs.size`).
class Awesome::Guards::InclusiveRangeIndex < Awesome::Guard
  LEVEL    = "vibecoder" # crashes on first run, not a style nit
  SEVERITY = "bug"       # runtime-breaker: IndexError on the last iteration

  SHORT_DESCRIPTION = <<-TEXT
    Checks for `(0..xs.size).each { |i| … xs[i] … }` and
    `1.upto(xs.size) { |i| … xs[i] … }` — the inclusive bound yields
    `i == xs.size` on the last iteration, and `xs[i]` raises
    IndexError. Use the exclusive `0...xs.size` or `xs.size.times`.
    Fires only when the block indexes that same receiver with the bare
    loop variable.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    (0...items.size).each do |i|
      process items[i]
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    (0..items.size).each do |i|
      process items[i]   # i == items.size on the last pass
    end
  CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end
end

Awesome::Guard.registered << Awesome::Guards::InclusiveRangeIndex
