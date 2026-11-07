# StoredLibPointer — a raw pointer obtained from a lib fun is stored
# in an ivar/class var/constant: its lifetime was decided on the C
# side, and the field says nothing about it.
#
# `@ctx = LibEngine.create()` — whether that pointer is a borrow (C
# owns it and may free/realloc it under our feet) or a transfer (we
# own it and must free it ourselves) is a contract no type in Crystal
# expresses. The AST cannot prove which one it is, so this is
# deliberately a "requires attention" marker (style), not a bug
# verdict: storing the raw value in a field is exactly the shape where
# a wrong assumption becomes a delayed crash — a use-after-free or a
# leak surfacing far from this line.
#
# Safer alternatives: wrap the pointer in a class whose API owns the
# contract explicitly (`#close` / `#finalize` that releases it), or
# hide the pointer behind a handle (an index into a Crystal-side
# table, the way the C host never holds a GC pointer at all), or keep
# it in a local for the duration of one call.
#
# Suppressions, so the marker only fires where attention is genuinely
# missing:
#   * allocator funs (`malloc`, `calloc`, …) are MemoryLeak's concern
#     — the pairing with `free` is already checked there;
#   * a `finalize` or `close` def anywhere in the file says the
#     project already manages the lifetime explicitly.
class Awesome::Guards::StoredLibPointer < Awesome::Guard
  KIND              = "memory"
  LEVEL             = "senior" # on by default: attention marker, not a bug
  SEVERITY          = "style"  # suspicion — the contract may well be safe
  SHORT_DESCRIPTION = <<-TEXT
    Checks that raw pointers from lib funs are not silently stored in
    ivars/class vars/constants. Whether C keeps ownership (a borrow
    that can dangle) or hands it over (a leak if never freed) is a
    contract the field doesn't express — a wrong guess crashes far
    from this line. Wrap the pointer with an explicit `#close`/
    `#finalize`, or hide it behind a handle into a Crystal-side table.
    Allocator funs (malloc/…) are skipped: MemoryLeak covers them.
    TEXT

  GOOD_EXAMPLE = <<-CODE
    lib LibEngine
      fun create : Void*
      fun destroy(ctx : Void*) : Void
    end

    class Context
      def initialize
        @ctx = LibEngine.create # ownership is explicit below
      end

      def close
        LibEngine.destroy(@ctx) # release where it was acquired
        @ctx = Pointer(Void).null
      end
    end
    CODE

  BAD_EXAMPLE = <<-CODE
    lib LibEngine
      fun create : Void*
    end

    class Context
      def initialize
        @ctx = LibEngine.create # borrow or own? nobody will ever know
      end
    end
    CODE

  # Allocator names excluded here because MemoryLeak already owns the
  # alloc/free pairing concern for them.
  DEFAULT_ALLOCATORS = ["malloc", "calloc", "realloc", "xmalloc", "strdup"]

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source, config.strings("allocators", DEFAULT_ALLOCATORS))
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  # A `finalize`/`close` def anywhere in the file: the project manages
  # C lifetimes explicitly — generous, file-granular suppression.
  private class LifecycleScanner < Crystal::Visitor
    getter? manages = false

    def visit(node : Crystal::Def)
      @manages = true if node.name.in?({"finalize", "close"})
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end
  end

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    @libs = Set(String).new # libs declared in this file
    @lib_stack = [] of String
    @manages_lifecycle = false

    def initialize(@source : Awesome::Source, @allocators : Array(String))
      if (ast = @source.ast)
        scanner = LifecycleScanner.new
        ast.accept(scanner)
        @manages_lifecycle = scanner.manages?
      end
    end

    def visit(node : Crystal::LibDef)
      @libs << node.name.to_s
      @lib_stack.push(node.name.to_s)
      node.body.accept(self)
      @lib_stack.pop
      false
    end

    def visit(node : Crystal::Assign)
      # Skip assignments inside lib bodies: fun definitions
      # (`fun x = ...`) define the shim, they don't use it.
      if @lib_stack.empty? && !@manages_lifecycle &&
         (target = node.target).is_a?(Crystal::InstanceVar | Crystal::ClassVar |
                                      Crystal::Path) &&
         (value = node.value).is_a?(Crystal::Call) &&
         (obj = value.obj).is_a?(Crystal::Path) &&
         @libs.includes?(obj.names.last) &&
         !@allocators.includes?(value.name)
        @issues << Awesome::Issue.new(
          @source.path,
          "StoredLibPointer",
          Awesome::I18n.t("guards.StoredLibPointer.main",
            target: target, value: value, lib: obj),
          value.location,
          @source.excerpt_at(value.location.try(&.line_number) || 0)
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

Awesome::Guard.registered << Awesome::Guards::StoredLibPointer
