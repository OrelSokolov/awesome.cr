# Visitor for SliceAsCString — see guards/slice_as_c_string.cr.
class Awesome::Guards::SliceAsCString::Visitor < Crystal::Visitor
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
        Awesome::I18n.t("guards.SliceAsCString.main",
          expr: arg, lib: lib_name, fun: call.name, param: param),
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
