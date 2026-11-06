# DoubleFree — the same pointer must not be passed to a lib-shim
# deallocator twice without a reassignment in between.
#
# Companion to MemoryLeak, same domain: `LibFoo.free(ptr)` releases C
# heap memory that the Crystal GC will never manage. Calling it twice
# on the same pointer corrupts the C heap (undefined behaviour, hard to
# debug crashes). The check: within one statement block, a second
# `free(ptr)` on a variable with no assignment to that variable between
# the two calls is always a bug — `ptr = LibFoo.malloc(...)` (or a
# `realloc`) in between is the only thing that makes the second free
# legal.
#
# Scope is deliberately narrow so there are no false positives:
# only element-level calls in the same statement list (`Expressions`)
# are paired, so frees in sibling `if`/`else` branches never fire, and
# any assignment to the variable anywhere between the calls (including
# inside blocks and nested expressions) suppresses the issue.
class Awesome::Guards::DoubleFree < Awesome::Guard
  SHORT_DESCRIPTION = <<-TEXT
    Checks that a pointer is not passed to a lib-shim deallocator twice
    without a reassignment in between. `LibC.free(ptr)` followed by
    another `LibC.free(ptr)` on the same unchanged variable is a double
    free — undefined behaviour that corrupts the C heap. Reassign the
    variable (`ptr = LibC.malloc(...)` / `realloc`) between the calls
    if you really allocate again.
    TEXT

  GOOD_EXAMPLE = <<-CODE
    lib LibGeo
      fun malloc(size : Int32) : Void*
      fun realloc(ptr : Void*, size : Int32) : Void*
      fun free(ptr : Void*)
    end

    def grow(ptr)
      ptr = LibGeo.realloc(ptr, 128) # fresh pointer...
      LibGeo.free(ptr)               # ...so this is the first free
    end
    CODE

  BAD_EXAMPLE = <<-CODE
    lib LibGeo
      fun malloc(size : Int32) : Void*
      fun free(ptr : Void*)
    end

    def close(ptr)
      LibGeo.free(ptr)
      cleanup
      LibGeo.free(ptr) # no reassignment in between — double free
    end
    CODE

  DEFAULT_DEALLOCATORS = ["free", "xfree"]

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    deallocators = config.strings("deallocators", DEFAULT_DEALLOCATORS)
    visitor = Visitor.new(source, deallocators)
    source.ast.try &.accept(visitor)
    visitor.analyze
    visitor.issues
  end

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    def initialize(@source : Awesome::Source, @deallocators : Array(String))
      @libs = {} of String => Array(String) # lib name → declared fun names
      @lib_stack = [] of String
      # Statement blocks are collected during traversal and paired after
      # it, so a lib declared anywhere in the file is known by then.
      @blocks = [] of Array(Crystal::ASTNode)
    end

    def visit(node : Crystal::LibDef)
      @lib_stack.push(node.name.to_s)
      node.body.accept(self)
      @lib_stack.pop
      false
    end

    def visit(node : Crystal::FunDef)
      unless @lib_stack.empty?
        (@libs[@lib_stack.last] ||= [] of String) << node.name
      end
      true
    end

    # Statement lists are where pairs are sought: frees in sibling
    # branches (each its own Expressions) are never paired.
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
      @blocks.each { |exprs| check_pairs(exprs) }
    end

    private def check_pairs(exprs : Array(Crystal::ASTNode)) : Nil
      first = {} of String => Crystal::Call # var name → first free call
      exprs.each do |expr|
        if (call = dealloc_call?(expr)) && (name = freed_var(call))
          if (prev = first[name]?)
            prev_line = prev.location.try(&.line_number) || 0
            @issues << Awesome::Issue.new(
              @source.path,
              "DoubleFree",
              "`#{call.obj}.#{call.name}(#{name})` frees `#{name}` again: " \
              "it was already freed at line #{prev_line} and nothing " \
              "reassigned `#{name}` in between — a double free corrupts " \
              "the C heap",
              call.location,
              @source.excerpt_at(call.location.try(&.line_number) || 0)
            )
          else
            first[name] = call
          end
        end
        # Any assignment to a tracked variable in this statement — even
        # nested in blocks or expressions — gives it a fresh value.
        first.reject! { |name, _| assigns?(expr, name) }
      end
    end

    # A statement-level `Lib.free(x)` call on a tracked C shim.
    private def dealloc_call?(node : Crystal::ASTNode) : Crystal::Call?
      return nil unless node.is_a?(Crystal::Call)
      return nil unless node.args.size == 1
      return nil unless (obj = node.obj).is_a?(Crystal::Path)
      return nil unless @deallocators.includes?(node.name)
      tracks?(obj.names.last) ? node : nil
    end

    # The freed expression, when it is a trackable local or ivar.
    private def freed_var(call : Crystal::Call) : String?
      case arg = call.args.first
      when Crystal::Var, Crystal::InstanceVar
        arg.to_s
      else
        nil
      end
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
  end
end

Awesome::Guard.registered << Awesome::Guards::DoubleFree
