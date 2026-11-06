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
  KIND     = "memory"
  LEVEL    = "vibecoder" # undefined behaviour, not a style nit
  SEVERITY = "bug"       # runtime-breaker: the exception crosses C frames
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

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    def initialize(@source : Awesome::Source)
      @libs = Set(String).new # libs declared in this file
      @lib_stack = [] of String
    end

    def visit(node : Crystal::LibDef)
      @libs << node.name.to_s
      @lib_stack.push(node.name.to_s)
      node.body.accept(self)
      @lib_stack.pop
      false
    end

    def visit(node : Crystal::Call)
      # Skip calls inside lib bodies: fun definitions don't use shims.
      return true unless @lib_stack.empty?
      if (obj = node.obj).is_a?(Crystal::Path) && tracks?(obj.names.last)
        node.args.each do |arg|
          check_proc(arg, "#{obj}.#{node.name}") if arg.is_a?(Crystal::ProcLiteral)
        end
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    private def check_proc(proc : Crystal::ProcLiteral, call : String) : Nil
      scanner = RaiseScanner.new
      proc.accept(scanner)
      scanner.raises.each do |raise_node|
        @issues << Awesome::Issue.new(
          @source.path,
          "RaiseInLibCallback",
          "`raise` inside the callback passed to `#{call}`: an exception " \
          "raised in Crystal code called from C unwinds through the " \
          "library's C frames — undefined behaviour, in practice an " \
          "abort. Signal the error via the callback's return value or " \
          "catch it inside the callback",
          raise_node.location,
          @source.excerpt_at(raise_node.location.try(&.line_number) || 0)
        )
      end
    end

    # A receiver is a tracked C shim when its lib is declared in this
    # file, or (for libs bound elsewhere, like stdlib's LibC) when it
    # follows the `Lib`-prefix naming convention.
    private def tracks?(name : String) : Bool
      @libs.includes?(name) || name.starts_with?("Lib")
    end
  end

  # Collects every `raise`/`reraise` in a subtree. In the parsed AST
  # both are plain calls (no dedicated Raise node before semantic
  # analysis), so match them by name.
  private class RaiseScanner < Crystal::Visitor
    getter raises = [] of Crystal::Call

    def visit(node : Crystal::Call)
      @raises << node if node.name.in?({"raise", "reraise"})
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::RaiseInLibCallback
