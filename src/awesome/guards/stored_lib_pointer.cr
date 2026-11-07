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
end

Awesome::Guard.registered << Awesome::Guards::StoredLibPointer
