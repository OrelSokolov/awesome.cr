# RaiseInLibCallback — a proc handed to a lib-shim fun must not raise:
# the exception would unwind through the library's C frames.
#
# `LibWatch.each(->(row : Int32) { raise "corrupt" })` passes a Crystal
# proc into C. When C calls back into it and the proc raises, the
# exception has to unwind the C frames the library used to make the
# call — the runtime cannot do that correctly (undefined behaviour; in
# practice the process aborts with a wrecked stack, far from the bug).
# The fix is to never let an exception cross the C boundary: signal the
# error through the callback's return value, or catch it inside.
#
# Scope is deliberately narrow so there are no false positives: only
# proc literals passed directly as arguments of a lib-shim call
# (`LibFoo.fun(->(x) { ... })`) are inspected, and any `raise`/`reraise`
# anywhere in the proc's subtree is flagged — even nested in blocks,
# because it still unwinds through C. A proc stored in a variable and
# passed later is not tracked (a false negative by design).
class Awesome::Guards::RaiseInLibCallback < Awesome::Guard
  KIND              = "memory"
  LEVEL             = "vibecoder" # undefined behaviour, not a style nit
  SEVERITY          = "bug"       # runtime-breaker: the exception crosses C frames
  SHORT_DESCRIPTION = <<-TEXT
    Checks that procs passed to lib-shim funs never raise. A `raise`
    inside a callback called from C unwinds through the library's C
    frames — undefined behaviour that aborts the process far from the
    bug. Signal errors through the callback's return value or catch
    them inside the callback.
    TEXT

  GOOD_EXAMPLE = <<-CODE
    lib LibWatch
      fun each(cb : Int32 -> Int32) : Void
    end

    LibWatch.each(->(row : Int32) {
      row < 0 ? 1 : 0 # error signalled via the return value
    })
    CODE

  BAD_EXAMPLE = <<-CODE
    lib LibWatch
      fun each(cb : Int32 -> Void) : Void
    end

    LibWatch.each(->(row : Int32) {
      raise "row is corrupt" # unwinds through LibWatch's C frames — UB
    })
    CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end
end

Awesome::Guard.registered << Awesome::Guards::RaiseInLibCallback
