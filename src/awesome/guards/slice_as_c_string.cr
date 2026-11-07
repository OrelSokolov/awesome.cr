# SliceAsCString — `x.to_unsafe` passed where the C side expects a
# NUL-terminated string, with no length argument in sight.
#
# `LibCfg.read(slice.to_unsafe)` hands C a raw buffer pointer. If the
# receiver is a String, the bytes are NUL-terminated and C reading them
# as a string is fine; if it is a Slice (or StaticArray), they are
# NOT — C's strlen/read runs past the buffer end, which is undefined
# behaviour: usually garbage, occasionally a segfault, always far from
# the call. The AST cannot tell String from Slice at the receiver, so
# this is deliberately a "requires attention" marker (style), not a
# bug verdict: the guard fires only when nothing at the call site says
# a length travels with the pointer (no `size`/`bytesize`/`length`/
# `count`/`cap` argument) — that is exactly the shape where a Slice
# receiver means an overread.
#
# Safer alternatives: pass the length next to the pointer
# (`LibCfg.read_n(buf.to_unsafe, buf.size)`), or make a terminated copy
# (`String.new(slice).to_unsafe` — allocates, but the contract is
# explicit), or bind the fun as taking `(data : UInt8*, len : Int32)`
# in the first place.
#
# A fun must be declared in this file to be checked: the parameter
# types (`UInt8*`/`Int8*`/`Char*`) come from its own `lib` declaration.
# Shims bound elsewhere (Lib-prefixed without a declaration) have an
# unknown signature — a false negative by design.
class Awesome::Guards::SliceAsCString < Awesome::Guard
  KIND     = "memory"
  LEVEL    = "senior"    # on by default: attention marker, not a bug
  SEVERITY = "style"     # suspicion — String receivers are fine here
  SHORT_DESCRIPTION = <<-TEXT
    Checks that `x.to_unsafe` passed to a `UInt8*`/`Int8*`/`Char*`
    parameter of a lib fun travels with a length argument. A String's
    bytes are NUL-terminated, a Slice's are not — C reading the
    pointer as a string overreads the buffer (UB). If the receiver
    might be a Slice, pass `x.size` alongside, copy via
    `String.new(x)`, or bind the fun as `(data : UInt8*, len : Int32)`.
    TEXT

  GOOD_EXAMPLE = <<-CODE
    lib LibCfg
      fun read_n(data : UInt8*, len : Int32) : Int32
    end

    LibCfg.read_n(buf.to_unsafe, buf.size) # pointer and its length
    CODE

  BAD_EXAMPLE = <<-CODE
    lib LibCfg
      fun read(name : UInt8*) : Int32
    end

    LibCfg.read(buf.to_unsafe) # buf is a Slice — no NUL, no length
    CODE

  # Argument expressions whose presence says a length travels with the
  # pointer (`read(buf.to_unsafe, buf.size)` is explicit and safe).
  DEFAULT_LENGTH_NAMES = {"size", "bytesize", "length", "len", "count", "cap"}

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source, config.strings("length_names", DEFAULT_LENGTH_NAMES.to_a))
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    @funs = {} of String => Array(Crystal::Arg) # "Lib.fun" → declared args
    @lib_stack = [] of String

    def initialize(@source : Awesome::Source, @length_names : Array(String))
    end

    def visit(node : Crystal::LibDef)
      @lib_stack.push(node.name.to_s)
      node.body.accept(self)
      @lib_stack.pop
      false
    end

    def visit(node : Crystal::FunDef)
      if lib_name = @lib_stack.last?
        @funs["#{lib_name}.#{node.name}"] = node.args
      end
      true
    end

    def visit(node : Crystal::Call)
      # Skip calls inside lib bodies: fun definitions don't use shims.
      return true unless @lib_stack.empty?
      if (obj = node.obj).is_a?(Crystal::Path) && (args = @funs["#{obj.names.last}.#{node.name}"]?)
        check(node, obj.names.last, args)
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    private def check(call : Crystal::Call, lib_name : String, fun_args : Array(Crystal::Arg)) : Nil
      # No length argument anywhere in the call — the pointer travels
      # alone, which is the shape where a Slice receiver overreads.
      return if call.args.any? { |a| length_arg?(a) }

      call.args.each_with_index do |arg, i|
        next unless (call_arg = to_unsafe_call(arg))
        next unless (param = fun_args[i]?) && char_pointer?(param.restriction)
        # A string literal receiver is NUL-terminated by construction.
        next if call_arg.obj.is_a?(Crystal::StringLiteral)
        @issues << Awesome::Issue.new(
          @source.path,
          "SliceAsCString",
          "`#{arg}` is passed to `#{lib_name}.#{call.name}`'s `#{param}` " \
          "(a C string parameter) with no length argument in the call: " \
          "if the receiver is a Slice, its bytes are not NUL-terminated " \
          "and C reading them as a string overreads the buffer " \
          "(undefined behaviour). Pass `x.size` alongside, copy via " \
          "`String.new(x)`, or bind the fun as " \
          "`(data : UInt8*, len : Int32)`",
          arg.location,
          @source.excerpt_at(arg.location.try(&.line_number) || 0)
        )
      end
    end

    private def to_unsafe_call(node : Crystal::ASTNode) : Crystal::Call?
      return nil unless node.is_a?(Crystal::Call) && node.name == "to_unsafe" &&
                        node.args.empty? && node.obj
      node
    end

    # `UInt8*` / `Int8*` / `Char*` parse as Pointer(T) generics.
    private def char_pointer?(restriction : Crystal::ASTNode?) : Bool
      return false unless restriction.is_a?(Crystal::Generic) &&
                          (name = restriction.name).is_a?(Crystal::Path) &&
                          name.names.last == "Pointer"
      if (tv = restriction.type_vars.first?).is_a?(Crystal::Path)
        tv.names.last.in?({"UInt8", "Int8", "Char"})
      else
        false
      end
    end

    # Whether an argument subtree carries a length (a call like
    # `buf.size`, or a bare var named like one — `len`, `count` …).
    private def length_arg?(arg : Crystal::ASTNode) : Bool
      scanner = LengthScanner.new(@length_names)
      arg.accept(scanner)
      scanner.found?
    end
  end

  private class LengthScanner < Crystal::Visitor
    getter? found = false

    def initialize(@length_names : Array(String))
    end

    def visit(node : Crystal::Call)
      @found = true if @length_names.includes?(node.name)
      true
    end

    def visit(node : Crystal::Var | Crystal::InstanceVar)
      @found = true if @length_names.includes?(node.to_s)
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::SliceAsCString
