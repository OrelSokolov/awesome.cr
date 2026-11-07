# RaiseInFunDef — a raise escaping a `fun` def unwinds into whatever
# C code called it.
#
# A top-level `fun vib_push(h : Int64) : Int64 ... end` is an ABI entry
# point: the plain C host (dlopen, a C library, another language's
# runtime) calls it directly. When Crystal code inside the fun raises,
# the exception must unwind the caller's foreign frames — the runtime
# cannot do that correctly; it is undefined behaviour, in practice an
# abort or a wrecked stack inside the host, far from the raise that
# caused it. This is the `fun`-def half of RaiseInLibCallback (which
# covers procs C calls back into): every exception crossing the C
# boundary in either direction is UB. The fix is the same discipline
# a C API uses — catch inside, return an error code:
#
#   fun vib_push(h : Int64) : Int64
#     state.push(h)
#     0
#   rescue
#     -1 # the host sees the error, the boundary stays intact
#   end
#
# Scope: any `raise`/`reraise` in a `fun` body that is not inside a
# `begin/rescue` (an ExceptionHandler node) of that body — a caught
# raise never crosses the boundary. Raises nested in blocks or proc
# literals within the fun are still flagged: they unwind through the
# fun either way. `fun x = ...` declarations inside a `lib` have no
# body and never fire.
class Awesome::Guards::RaiseInFunDef < Awesome::Guard
  KIND     = "memory"
  LEVEL    = "vibecoder" # undefined behaviour, not a style nit
  SEVERITY = "bug"       # runtime-breaker: the exception crosses C frames
  SHORT_DESCRIPTION = <<-TEXT
    Checks that `fun` defs never let an exception escape. A `fun` is
    an ABI entry point called from C; a `raise` inside it unwinds
    through the caller's foreign frames — undefined behaviour, in
    practice an abort far from the bug. Catch inside the fun and
    return an error code instead. Raises inside a `begin/rescue` in
    the fun body are fine (they don't reach the boundary).
    TEXT

  GOOD_EXAMPLE = <<-CODE
    fun vib_push(h : Int64) : Int64
      state.push(h)
      0
    rescue
      -1 # error signalled via the return value
    end
    CODE

  BAD_EXAMPLE = <<-CODE
    fun vib_push(h : Int64) : Int64
      raise "bad handle" # unwinds into the C host — undefined behaviour
    end
    CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    def initialize(@source : Awesome::Source)
      @in_fun = false       # inside a `fun` def body
      @in_handler = false   # inside a begin/rescue of that body
    end

    def visit(node : Crystal::FunDef)
      # Only `fun name ... end` defs have a body; `fun x = ...` inside
      # a lib is a declaration and parses with body == nil.
      if (body = node.body) && !@in_fun
        @in_fun = true
        body.accept(self)
        @in_fun = false
      end
      false
    end

    def visit(node : Crystal::ExceptionHandler)
      # A caught raise never reaches the C boundary. The flag covers
      # the whole subtree: a reraise in a rescue body is a false
      # negative by design (keep the guard loud-but-safe).
      if @in_fun
        @in_handler = true
        node.accept_children(self)
        @in_handler = false
        return false
      end
      true
    end

    def visit(node : Crystal::Call)
      # In the parsed AST raise/reraise are plain calls (no dedicated
      # Raise node before semantic analysis), so match them by name.
      if @in_fun && !@in_handler && node.name.in?({"raise", "reraise"})
        @issues << Awesome::Issue.new(
          @source.path,
          "RaiseInFunDef",
          "`#{node.name}` inside a `fun` def: an exception escaping an " \
          "ABI entry point unwinds through the C caller's frames — " \
          "undefined behaviour, in practice an abort far from the bug. " \
          "Catch inside the fun and return an error code",
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

Awesome::Guard.registered << Awesome::Guards::RaiseInFunDef
