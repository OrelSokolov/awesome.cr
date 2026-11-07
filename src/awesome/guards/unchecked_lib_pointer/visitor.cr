# Visitor for UncheckedLibPointer — see guards/unchecked_lib_pointer.cr.
class Awesome::Guards::UncheckedLibPointer::Visitor < Crystal::Visitor
  getter issues = [] of Awesome::Issue

  def initialize(@source : Awesome::Source)
    @libs = {} of String => Set(String) # lib name → funs returning T*
    @lib_stack = [] of String
    # Statement blocks are collected during traversal and paired after
    # it, so a lib declared anywhere in the file is known by then.
    @blocks = [] of Array(Crystal::ASTNode)
  end

  def visit(node : Crystal::LibDef)
    @lib_stack.push(node.name.to_s)
    @libs[node.name.to_s] ||= Set(String).new
    node.body.accept(self)
    @lib_stack.pop
    false
  end

  def visit(node : Crystal::FunDef)
    if (lib_name = @lib_stack.last?) && (ret = node.return_type)
      # `T*` / `Pointer(T)` parse as Generic with a Pointer name.
      if ret.is_a?(Crystal::Generic) && (name = ret.name).is_a?(Crystal::Path) && name.names.last == "Pointer"
        @libs[lib_name] << node.name
      end
    end
    true
  end

  # Statement lists are where the stored shape is paired; sibling
  # branches (each its own Expressions) never mix.
  def visit(node : Crystal::Expressions)
    @blocks << node.expressions
    true
  end

  # Fallback: redefining `visit` in a subclass replaces the base
  # class's overloads, so re-enable traversal for everything else.
  def visit(node : Crystal::ASTNode)
    true
  end

  # Runs after the traversal, once every lib in the file is known.
  def analyze : Nil
    # The chained shape is scope-independent — scan the whole tree.
    chained = ChainScanner.new(@source, @libs, @issues)
    @source.ast.try &.accept(chained)
    @blocks.each { |exprs| check_block(exprs) }
  end

  private def check_block(exprs : Array(Crystal::ASTNode)) : Nil
    origins = {} of String => Crystal::Call # var name → assigning call
    exprs.each do |expr|
      # Any assignment to a tracked variable in this statement — even
      # nested in blocks — gives it a fresh (untracked) value.
      origins.reject! { |name, _| assigns?(expr, name) }
      if expr.is_a?(Crystal::Assign) && (target = expr.target).is_a?(Crystal::Var | Crystal::InstanceVar) && (call = lib_call?(expr.value))
        origins[target.to_s] = call
        next
      end
      # A null check (`if point`, `unless point.nil?`, `while point`)
      # anywhere in the statement — including an `if` wrapping the
      # deref itself — makes the variable safe from here on.
      origins.reject! { |name, _| checked?(expr, name) }
      expr.accept(DerefScanner.new(@source, @libs, origins, @issues))
    end
  end

  # A call on a tracked C shim that can hand back a raw pointer.
  private def lib_call?(node : Crystal::ASTNode) : Crystal::Call?
    return nil unless node.is_a?(Crystal::Call)
    return nil unless (obj = node.obj).is_a?(Crystal::Path)
    return nil unless tracks?(obj.names.last)
    # A lib declared in the file must actually return T* — for the
    # deref to compile, only those funs matter anyway.
    if (funs = @libs[obj.names.last]?) && !funs.includes?(node.name)
      return nil
    end
    node
  end

  # A receiver is a tracked C shim when its lib is declared in this
  # file, or (for libs bound elsewhere, like stdlib's LibC) when it
  # follows the `Lib`-prefix naming convention.
  private def tracks?(name : String) : Bool
    @libs.has_key?(name) || name.starts_with?("Lib")
  end

  private def assigns?(expr : Crystal::ASTNode, name : String) : Bool
    scanner = AssignScanner.new(name)
    expr.accept(scanner)
    scanner.found?
  end

  private def checked?(expr : Crystal::ASTNode, name : String) : Bool
    scanner = CheckScanner.new(name)
    expr.accept(scanner)
    scanner.checked?
  end
end
