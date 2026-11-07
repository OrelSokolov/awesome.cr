# UnpinnedLibCallback — a closure handed to a storing lib fun with no
# reference kept on the Crystal side.
#
# `LibUi.on_click(->(b : Int32) { ... })` passes a Crystal proc into C.
# The proc's code and captured environment live in the Boehm-GC heap,
# and an inline literal has no reference once the call returns — only
# the (conservatively scanned) stack keeps it alive during the call
# itself. If the library *stores* the callback and invokes it later,
# the collector may have freed the closure by then: the next callback
# from C dereferences a dead object and crashes, typically long after
# the registration, far from the bug. The fix is to keep the closure
# alive for as long as C holds it: assign the proc to a constant or a
# class variable and pass that, or pin the memory with `GC.add_root`.
#
# Scope mirrors RaiseInLibCallback (only literals at the call site are
# tracked), plus the storage question: the guard fires only on fun
# names that say the library keeps the callback (`on_click`,
# `set_logger`, `register_handler` — set_/register_/on_/add_/attach_/
# subscribe_ prefixes, or callback/handler/listener/hook in the name).
# Fire-and-forget shims (`LibC.qsort(...)`) are skipped by design: the
# closure is stack-reachable for the whole call there.
class Awesome::Guards::UnpinnedLibCallback < Awesome::Guard
  KIND              = "memory"
  LEVEL             = "vibecoder" # a delayed use-after-free, not a style nit
  SEVERITY          = "bug"       # runtime-breaker: the GC frees a stored closure
  SHORT_DESCRIPTION = <<-TEXT
    Checks that closures passed to storing lib-shim funs are kept
    alive. A proc literal (`->(x) { ... }`) or `Box.box(x)` passed
    inline to `LibFoo.set_callback`-style funs has no reference once
    the call returns; if the library stores it, the Boehm GC can free
    the closure and the next callback from C is a use-after-free.
    Assign the proc (or box) to a constant/class variable and pass
    that, or pin it with `GC.add_root`.
    TEXT

  GOOD_EXAMPLE = <<-CODE
    lib LibUi
      fun on_click(cb : Int32 -> Void) : Void
    end

    # A constant holds the closure alive for the whole program —
    # exactly as long as LibUi keeps the callback.
    ON_CLICK = ->(button : Int32) { Counter.add(button) }

    LibUi.on_click(ON_CLICK)
    CODE

  BAD_EXAMPLE = <<-CODE
    lib LibUi
      fun on_click(cb : Int32 -> Void) : Void
    end

    LibUi.on_click(->(button : Int32) { # inline literal: unreferenced
      Counter.add(button)              # once the GC runs — crash
    })
    CODE

  # Fun names that say the library keeps the callback past the call.
  STORAGE_PREFIXES   = {"set_", "register_", "on_", "add_", "attach_", "subscribe_"}
  STORAGE_SUBSTRINGS = {"callback", "handler", "listener", "hook"}

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source, config.strings("storage_funs", [] of String),
      config.strings("ignore_funs", [] of String))
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    @ignored = [] of String

    def initialize(@source : Awesome::Source, @extra_storage_funs : Array(String),
                   ignored_funs : Array(String))
      @libs = Set(String).new # libs declared in this file
      @lib_stack = [] of String
      @ignored = ignored_funs
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
      if (obj = node.obj).is_a?(Crystal::Path) && tracks?(obj.names.last) &&
         stores?(node.name)
        node.args.each do |arg|
          check_arg(arg, "#{obj}.#{node.name}")
        end
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    private def check_arg(arg : Crystal::ASTNode, call : String) : Nil
      case arg
      when Crystal::ProcLiteral
        @issues << Awesome::Issue.new(
          @source.path,
          "UnpinnedLibCallback",
          Awesome::I18n.t("guards.UnpinnedLibCallback.main", call: call),
          arg.location,
          @source.excerpt_at(arg.location.try(&.line_number) || 0)
        )
      when Crystal::Call
        # Box.box(x) / Box.new(x): the box is GC-managed like the proc.
        if arg.name.in?({"box", "new"}) && (obj = arg.obj).is_a?(Crystal::Path) &&
           obj.names.last == "Box"
          @issues << Awesome::Issue.new(
            @source.path,
            "UnpinnedLibCallback",
            Awesome::I18n.t("guards.UnpinnedLibCallback.boxed", box: arg, call: call),
            arg.location,
            @source.excerpt_at(arg.location.try(&.line_number) || 0)
          )
        end
      end
    end

    # Whether the fun keeps the callback past the call — by naming
    # convention, an exact name from the config (`storage_funs`), or
    # never for names in `ignore_funs` (a storing-looking name that
    # actually doesn't store — the suppression valve for the heuristic).
    private def stores?(name : String) : Bool
      return false if @ignored.includes?(name)

      @extra_storage_funs.includes?(name) ||
        STORAGE_PREFIXES.any? { |p| name.starts_with?(p) } ||
        STORAGE_SUBSTRINGS.any? { |s| name.includes?(s) }
    end

    # A receiver is a tracked C shim when its lib is declared in this
    # file, or (for libs bound elsewhere, like stdlib's LibC) when it
    # follows the `Lib`-prefix naming convention.
    private def tracks?(name : String) : Bool
      @libs.includes?(name) || name.starts_with?("Lib")
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::UnpinnedLibCallback
