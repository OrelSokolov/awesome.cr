# PointerOfEscape — `pointerof(x)` handed to a storing lib fun (or
# kept in a field): the address is only as alive as its owner.
#
# `LibStats.register_counter(pointerof(@count))` gives C the address
# of an ivar. Boehm doesn't move objects, so the address itself stays
# valid — but the *object holding the ivar* is GC-managed, and the
# collector does not scan C memory: once the instance is unreachable
# on the Crystal side, the next tick of C's counter writes through a
# dangling pointer. The AST cannot prove the owner outlives C's use,
# so this is deliberately a "requires attention" marker (style), not a
# bug verdict. The same applies to a field keeping `pointerof(x)`:
# the field pins the address, not the owner.
#
# Safer alternatives: pass a value C copies (register the number, not
# the address); or hand C a Box (see UnpinnedLibCallback for keeping
# it alive); or allocate the C-side counter with malloc and own it
# explicitly (then MemoryLeak's pairing applies).
#
# The storage question reuses UnpinnedLibCallback's convention: fun
# names that say the library keeps the argument (`set_*`,
# `register_*`, `on_*`, `add_*`, `attach_*`, `subscribe_*` prefixes,
# or callback/handler/listener/hook in the name; more via config).
# `pointerof` passed to fire-and-forget funs (`LibFoo.fill(ptr, n)`)
# is the intended use and never fires.
class Awesome::Guards::PointerOfEscape < Awesome::Guard
  KIND     = "memory"
  LEVEL    = "senior"    # on by default: attention marker, not a bug
  SEVERITY = "style"     # suspicion — the owner may well be immortal
  SHORT_DESCRIPTION = <<-TEXT
    Checks that `pointerof(x)` doesn't reach a storing lib fun or a
    field. The address is stable (Boehm doesn't move objects), but its
    owner is GC-managed and invisible to C: once the owner is
    collected, C holds a dangling address. Pass a value C copies, use
    a Box (kept alive — see UnpinnedLibCallback), or malloc the memory
    and own it explicitly.
    TEXT

  GOOD_EXAMPLE = <<-CODE
    lib LibStats
      fun register_counter(value : Int32) : Void # C copies the number
    end

    LibStats.register_counter(@count)
    CODE

  BAD_EXAMPLE = <<-CODE
    lib LibStats
      fun register_counter(addr : Int32*) : Void
    end

    # C keeps the address of a GC-managed ivar
    LibStats.register_counter(pointerof(@count))
    CODE

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

    @libs = Set(String).new # libs declared in this file
    @lib_stack = [] of String
    @ignored = [] of String

    def initialize(@source : Awesome::Source, @extra_storage_funs : Array(String),
                   ignored_funs : Array(String))
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
          next unless arg.is_a?(Crystal::PointerOf)
          report(arg,
            "`#{arg}` passed to `#{obj}.#{node.name}`: the address is " \
            "stable but its owner is GC-managed and invisible to C — " \
            "once the owner is collected, the library writes through a " \
            "dangling pointer. Pass a value C copies, use a Box kept " \
            "alive (see UnpinnedLibCallback), or malloc the memory and " \
            "own it explicitly")
        end
      end
      true
    end

    def visit(node : Crystal::Assign)
      if @lib_stack.empty? &&
         (target = node.target).is_a?(Crystal::InstanceVar | Crystal::ClassVar |
                                      Crystal::Path) &&
         (value = node.value).is_a?(Crystal::PointerOf)
        report(value,
          "`#{target} = #{value}` pins the address but not its owner: " \
          "the object holding the variable is GC-managed and the field " \
          "keeps only the raw address — after a collection the pointer " \
          "dangles. Keep the owner alive next to the field, or malloc " \
          "the memory and own it explicitly")
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    private def report(node : Crystal::ASTNode, message : String) : Nil
      @issues << Awesome::Issue.new(
        @source.path,
        "PointerOfEscape",
        message,
        node.location,
        @source.excerpt_at(node.location.try(&.line_number) || 0)
      )
    end

    # Whether the fun keeps the argument past the call — by naming
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

Awesome::Guard.registered << Awesome::Guards::PointerOfEscape
