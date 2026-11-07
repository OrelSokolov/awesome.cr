# SelfSizeIndex — `xs[xs.size]` indexes one past the last element.
#
# The classic off-by-one: for every stdlib container the last valid
# index is `size - 1`, so `xs[xs.size]` raises the moment it runs
# (Array/String: IndexError; Hash: KeyError). No receiver makes the
# pattern legal, which is what makes it provable syntactically.
#
# Two forms are caught: the direct `xs[xs.size]`, and the alias
# `n = xs.size … xs[n]` — the alias is tracked within one statement
# block, DoubleFree-style, and any reassignment of `n` in between
# clears it. `[]?` is skipped: `xs[xs.size]?` is the deliberate
# nil-on-miss form, not a crash.
class Awesome::Guards::SelfSizeIndex < Awesome::Guard
  LEVEL    = "vibecoder" # crashes on first run, not a style nit
  SEVERITY = "bug"       # runtime-breaker: guaranteed IndexError/KeyError

  SHORT_DESCRIPTION = <<-TEXT
    Checks for indexing a collection by its own size: `xs[xs.size]` (or
    `n = xs.size … xs[n]`) — valid indices run 0..size - 1, so the
    access is always out of bounds. The last element is `xs.last` /
    `xs[size - 1]`. The nilable `xs[xs.size]?` form is left alone.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    last = items[items.size - 1]
    first_empty = items[items.size]? # deliberate nil-on-miss
  CODE

  BAD_EXAMPLE = <<-CODE
    last = items[items.size] # one past the end — IndexError

    n = rows.size
    tail = rows[n]           # same bug through an alias
  CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.analyze
    visitor.issues
  end
end

Awesome::Guard.registered << Awesome::Guards::SelfSizeIndex
