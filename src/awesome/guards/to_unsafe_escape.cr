# ToUnsafeEscape — a `to_unsafe` pointer kept beyond the call it was
# made for.
#
# `String#to_unsafe` / `Slice#to_unsafe` return a raw pointer into the
# object's bytes — memory that lives in the Boehm-GC heap. The pointer
# is valid for the duration of the C call it was passed to (the object
# is reachable and Boehm doesn't move objects), but it is not a loan
# the Crystal side can forget: the backing object is collectable the
# moment nothing on the Crystal side references it, because the
# collector does not scan C memory — an ivar holding just the pointer
# keeps nothing alive. Storing `data.to_unsafe` in an ivar or a class
# var or a constant, or returning it from a method, creates exactly that
# dangling setup: the next GC cycle can free the bytes, and the crash
# shows up much later, in C code reading a buffer that no longer
# exists. The same holds after a buffer grows — `push` reallocates and
# the old pointer is garbage even without the GC.
#
# The fix is to keep the owner alive next to the pointer (hold the
# String/Slice in another ivar for as long as the pointer lives), or
# copy the bytes into C-owned memory and manage that lifetime
# explicitly (malloc + free — see MemoryLeak/DoubleFree).
#
# Scope is deliberately narrow so there are no false positives: only
# an assignment whose value *is* the `to_unsafe` call (`@ptr = x.to_unsafe`)
# and an explicit `return x.to_unsafe` are flagged. Pointers passed
# straight into a lib call (`LibFoo.draw(x.to_unsafe)`) are the
# intended use and never fire; wrapping shapes (`x.to_unsafe.as(Int8*)`,
# pointer arithmetic) are a false negative by design.
class Awesome::Guards::ToUnsafeEscape < Awesome::Guard
  KIND              = "memory"
  LEVEL             = "vibecoder" # a delayed dangling pointer, not a style nit
  SEVERITY          = "bug"       # runtime-breaker: the GC frees the backing bytes
  SHORT_DESCRIPTION = <<-TEXT
    Checks that `to_unsafe` pointers don't outlive their call. Storing
    `x.to_unsafe` in an ivar/class var/constant or returning it
    keeps a raw pointer into the GC heap while keeping nothing alive:
    the collector does not scan C memory, so the backing object can be
    freed and the pointer dangles. Keep the owner alive next to the
    pointer, or copy the bytes into C-owned memory.
    TEXT

  GOOD_EXAMPLE = <<-CODE
    class Decoder
      def initialize(@blob : Slice(UInt8))
        @raw = @blob.to_unsafe  # pointer...
        @keep = @blob           # ...and its owner, alive as long as @raw
      end

      def draw
        LibFoo.draw(@raw, @blob.size) # passed straight into the call
      end
    end
    CODE

  BAD_EXAMPLE = <<-CODE
    class Decoder
      def initialize(@blob : Slice(UInt8))
        @raw = @blob.to_unsafe # ivar keeps the pointer, not the slice —
      end                      # one GC cycle later @raw dangles

      def raw_ptr
        return @blob.to_unsafe # the caller outlives @blob's next GC
      end
    end
    CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  # Names of variables that are stored into an ivar/class var/constant
  # anywhere in the file (`@keep = @blob`, `KEEP = blob`): their owner
  # is reachable for as long as that field lives, so a to_unsafe
  # pointer taken from them stays valid. File-granular on purpose —
  # generous suppression beats false positives on a crash guard.
  private class KeeperScanner < Crystal::Visitor
    getter kept = Set(String).new

    def visit(node : Crystal::Assign)
      if node.target.is_a?(Crystal::InstanceVar | Crystal::ClassVar | Crystal::Path) &&
         (value = node.value).is_a?(Crystal::Var | Crystal::InstanceVar)
        @kept << value.to_s
      end
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end
  end

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    @kept = Set(String).new

    def initialize(@source : Awesome::Source)
      if (ast = @source.ast)
        scanner = KeeperScanner.new
        ast.accept(scanner)
        @kept = scanner.kept
      end
    end

    def visit(node : Crystal::Assign)
      if (target = node.target).is_a?(Crystal::InstanceVar | Crystal::ClassVar |
                                      Crystal::Path) &&
         (value = node.value) && (call = to_unsafe_call(value)) && !kept?(call)
        report(value,
          Awesome::I18n.t("guards.ToUnsafeEscape.main", target: target))
      end
      true
    end

    def visit(node : Crystal::Return)
      if (exp = node.exp) && (call = to_unsafe_call(exp)) && !kept?(call)
        report(exp,
          Awesome::I18n.t("guards.ToUnsafeEscape.return"))
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    private def to_unsafe_call(node : Crystal::ASTNode) : Crystal::Call?
      return nil unless node.is_a?(Crystal::Call) && node.name == "to_unsafe" && node.args.empty?
      node
    end

    # The receiver of a to_unsafe call whose owner is stored alive
    # somewhere (`@keep = @blob` next to `@raw = @blob.to_unsafe`).
    private def kept?(to_unsafe : Crystal::Call) : Bool
      (obj = to_unsafe.obj).is_a?(Crystal::Var | Crystal::InstanceVar) &&
        @kept.includes?(obj.to_s)
    end

    private def report(node : Crystal::ASTNode, message : String) : Nil
      @issues << Awesome::Issue.new(
        @source.path,
        "ToUnsafeEscape",
        message,
        node.location,
        @source.excerpt_at(node.location.try(&.line_number) || 0)
      )
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::ToUnsafeEscape
