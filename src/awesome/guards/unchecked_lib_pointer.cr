# UncheckedLibPointer — a pointer from a lib-shim fun must be null-
# checked before it is dereferenced.
#
# A C fun returning `T*` maps to `Pointer(T)` in Crystal, and C happily
# returns NULL from them ("not found", "out of range", "error"). The
# Crystal type says nothing about that, so `.value` on a NULL pointer is
# a segfault. Two shapes are always suspect:
#
#   LibGeo.find(id).value        # chained: deref right at the call
#   point = LibGeo.find(id)
#   point.value                  # stored: no check in between
#
# The chained shape is flagged wherever it appears. The stored shape is
# paired within one statement block (like DoubleFree): an assignment
# from a `T*`-returning lib fun starts tracking, and a `.value` on the
# unchanged variable is flagged — unless the variable appears in an
# `if`/`unless`/`while`/`until` condition in between (`if point ...`),
# gets a `.nil?`/`.null?` check, or is reassigned. Those all suppress
# the issue, so sibling branches and guarded derefs never fire.
#
# A lib declared in the file is checked precisely: only funs declared
# to return `T*`/`Pointer(T)` count. Lib-prefixed shims bound elsewhere
# (stdlib's `LibC`) can't be verified, so any of their funs is assumed
# to return a pointer — `.value` on the result of anything else
# (numbers, structs) wouldn't compile anyway.
class Awesome::Guards::UncheckedLibPointer < Awesome::Guard
  KIND              = "memory"
  LEVEL             = "vibecoder" # a NULL deref, not a style nit
  SEVERITY          = "bug"       # runtime-breaker: segfault on a NULL pointer
  SHORT_DESCRIPTION = <<-TEXT
    Checks that pointers returned by lib-shim funs are null-checked
    before `.value`. A C fun returning `T*` can return NULL ("not
    found"), and dereferencing it is a segfault. Both
    `LibGeo.find(id).value` and `point = LibGeo.find(id); point.value`
    (no `if point` in between) are flagged.
    TEXT

  GOOD_EXAMPLE = <<-CODE
    lib LibGeo
      fun find(id : Int32) : Float64*
    end

    def fetch(id)
      if point = LibGeo.find(id) # NULL-checked right at the source
        point.value
      end
    end
    CODE

  BAD_EXAMPLE = <<-CODE
    lib LibGeo
      fun find(id : Int32) : Float64*
    end

    def fetch(id)
      point = LibGeo.find(id)
      point.value # no null check in between — segfault when NULL
    end
    CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.analyze
    visitor.issues
  end
end

Awesome::Guard.registered << Awesome::Guards::UncheckedLibPointer
