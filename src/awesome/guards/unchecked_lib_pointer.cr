# UncheckedLibPointer — a pointer from a lib-shim fun must be null-
# checked before it is dereferenced.
#
# A C fun returning `T*` maps to `Pointer(T)` in Crystal, and C happily
# returns NULL from them ("not found", "out of range", "error"). The
# Crystal type says nothing about that, so `.value` on a NULL pointer is
# a segfault. Two shapes are always suspect:
#
#   LibGeo.find(id).value        # chained: deref right at the call
#   point = LibGeo.find(id)
#   point.value                  # stored: no check in between
#
# The chained shape is flagged wherever it appears. The stored shape is
# paired within one statement block (like DoubleFree): an assignment
# from a `T*`-returning lib fun starts tracking, and a `.value` on the
# unchanged variable is flagged — unless the variable appears in an
# `if`/`unless`/`while`/`until` condition in between (`if point ...`),
# gets a `.nil?`/`.null?` check, or is reassigned. Those all suppress
# the issue, so sibling branches and guarded derefs never fire.
#
# A lib declared in the file is checked precisely: only funs declared
# to return `T*`/`Pointer(T)` count. Lib-prefixed shims bound elsewhere
# (stdlib's `LibC`) can't be verified, so any of their funs is assumed
# to return a pointer — `.value` on the result of anything else
# (numbers, structs) wouldn't compile anyway.
class Awesome::Guards::UncheckedLibPointer < Awesome::Guard
  KIND     = "memory"
  LEVEL    = "vibecoder" # a NULL deref, not a style nit
  SEVERITY = "bug"       # runtime-breaker: segfault on a NULL pointer
  SHORT_DESCRIPTION = <<-TEXT
    Checks that pointers returned by lib-shim funs are null-checked
    before `.value`. A C fun returning `T*` can return NULL ("not
    found"), and dereferencing it is a segfault. Both
    `LibGeo.find(id).value` and `point = LibGeo.find(id); point.value`
    (no `if point` in between) are flagged.
    TEXT

  GOOD_EXAMPLE = <<-CODE
    lib LibGeo
      fun find(id : Int32) : Float64*
    end

    def fetch(id)
      if point = LibGeo.find(id) # NULL-checked right at the source
        point.value
      end
    end
    CODE

  BAD_EXAMPLE = <<-CODE
    lib LibGeo
      fun find(id : Int32) : Float64*
    end

    def fetch(id)
      point = LibGeo.find(id)
      point.value # no null check in between — segfault when NULL
    end
    CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.analyze
    visitor.issues
  end

  private class Visitor < Crystal::Visitor
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

    # Flags any assignment (`=`, op-assign, multi-assign) to a given
    # local/ivar name, anywhere in a subtree.
    private class AssignScanner < Crystal::Visitor
      getter? found = false

      def initialize(@name : String)
      end

      def visit(node : Crystal::Assign)
        check(node.target)
        true
      end

      def visit(node : Crystal::OpAssign)
        check(node.target)
        true
      end

      def visit(node : Crystal::MultiAssign)
        node.targets.each { |t| check(t) }
        true
      end

      def visit(node : Crystal::ASTNode)
        true
      end

      private def check(target : Crystal::ASTNode)
        case target
        when Crystal::Var, Crystal::InstanceVar
          @found = true if target.to_s == @name
        end
      end
    end

    # Flags a null check of the variable: an `if`/`unless`/`while`/
    # `until` condition mentioning it, or an explicit `.nil?`/`.null?`.
    private class CheckScanner < Crystal::Visitor
      getter? checked = false

      def initialize(@name : String)
      end

      def visit(node : Crystal::If)
        scan_cond(node.cond)
        true
      end

      def visit(node : Crystal::Unless)
        scan_cond(node.cond)
        true
      end

      def visit(node : Crystal::While)
        scan_cond(node.cond)
        true
      end

      def visit(node : Crystal::Until)
        scan_cond(node.cond)
        true
      end

      def visit(node : Crystal::Call)
        if node.name.in?({"nil?", "null?"}) && (obj = node.obj) && obj.to_s == @name
          @checked = true
        end
        true
      end

      def visit(node : Crystal::ASTNode)
        true
      end

      private def scan_cond(cond : Crystal::ASTNode) : Nil
        scanner = NameScanner.new(@name)
        cond.accept(scanner)
        @checked = true if scanner.found?
      end
    end

    # Whether a condition subtree mentions the variable at all.
    private class NameScanner < Crystal::Visitor
      getter? found = false

      def initialize(@name : String)
      end

      def visit(node : Crystal::Var)
        @found = true if node.to_s == @name
        true
      end

      def visit(node : Crystal::InstanceVar)
        @found = true if node.to_s == @name
        true
      end

      def visit(node : Crystal::Assign)
        @found = true if node.target.to_s == @name
        true
      end

      def visit(node : Crystal::ASTNode)
        true
      end
    end

    # The chained shape: `LibFoo.find(x).value` — dereference right on
    # the result of a pointer-returning lib call.
    private class ChainScanner < Crystal::Visitor
      def initialize(@source : Awesome::Source, @libs : Hash(String, Set(String)), @issues : Array(Awesome::Issue))
      end

      def visit(node : Crystal::Call)
        if node.name == "value" && (obj = node.obj).is_a?(Crystal::Call) &&
           (receiver = obj.obj).is_a?(Crystal::Path) && qualifies?(receiver.names.last, obj)
          @issues << Awesome::Issue.new(
            @source.path,
            "UncheckedLibPointer",
            "`#{obj}.value` dereferences the pointer returned by " \
            "`#{receiver}.#{obj.name}` on the spot: a C fun returning " \
            "`T*` can return NULL — capture it and check first " \
            "(`if ptr = #{receiver}.#{obj.name}(...)`)",
            node.location,
            @source.excerpt_at(node.location.try(&.line_number) || 0)
          )
        end
        true
      end

      def visit(node : Crystal::ASTNode)
        true
      end

      private def qualifies?(lib_name : String, call : Crystal::Call) : Bool
        if funs = @libs[lib_name]?
          funs.includes?(call.name) # declared here: must return T*
        else
          lib_name.starts_with?("Lib") # bound elsewhere: assume a pointer
        end
      end
    end

    # The stored shape: `.value` on a variable tracked from a lib call
    # assignment in the same statement block.
    private class DerefScanner < Crystal::Visitor
      def initialize(@source : Awesome::Source, @libs : Hash(String, Set(String)),
                     @origins : Hash(String, Crystal::Call), @issues : Array(Awesome::Issue))
      end

      def visit(node : Crystal::Call)
        if node.name == "value" && (obj = node.obj).is_a?(Crystal::Var | Crystal::InstanceVar) && (assign = @origins[obj.to_s]?)
          assign_line = assign.location.try(&.line_number) || 0
          @issues << Awesome::Issue.new(
            @source.path,
            "UncheckedLibPointer",
            "`#{obj}.value` dereferences the pointer `#{obj}` got from " \
            "`#{assign}` at line #{assign_line} without a null check in " \
            "between: a C fun returning `T*` can return NULL — " \
            "`if #{obj}` / `#{obj}.nil?` first",
            node.location,
            @source.excerpt_at(node.location.try(&.line_number) || 0)
          )
        end
        true
      end

      # Nested scopes have their own variables; their blocks are paired
      # separately (a Def body is its own statement list).
      def visit(node : Crystal::Def)
        false
      end

      def visit(node : Crystal::ClassDef)
        false
      end

      def visit(node : Crystal::ModuleDef)
        false
      end

      def visit(node : Crystal::LibDef)
        false
      end

      def visit(node : Crystal::ASTNode)
        true
      end
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::UncheckedLibPointer
