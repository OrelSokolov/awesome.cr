# MemoryLeak — C heap allocations from lib shims must be paired with a
# matching free somewhere in the file.
#
# `lib LibFoo ... fun malloc(...)` binds raw C allocators into Crystal.
# Memory they return lives on the C heap — the Crystal GC never frees
# it. The base check: every file that calls `LibFoo.malloc` (or any
# allocator fun) must also call `LibFoo.free` (or any deallocator fun)
# at least once. Zero free calls anywhere means the allocation can
# never be released — a certain leak, not a style nit.
#
# No C parsing is needed: shims are `Crystal::LibDef` / `Crystal::FunDef`
# nodes and call sites are `Call`s with a `Path` receiver, so the guard
# works on the compiler's own AST. Libs not declared in the file (e.g.
# stdlib's `LibC`) are still tracked via the `Lib`-prefix naming
# convention; non-lib receivers (`Foo.malloc`) are never flagged.
class Awesome::Guards::MemoryLeak < Awesome::Guard
  KIND  = "memory"
  LEVEL = "vibecoder" # a certain leak, not a style nit
  SHORT_DESCRIPTION = <<-TEXT
    Checks that C heap allocations from lib shims are paired with a
    matching free. `LibFoo.malloc` / `LibC.calloc` and friends return
    memory the Crystal GC will never release; if a file calls an
    allocator fun but never calls a deallocator fun (`LibFoo.free`)
    anywhere in it, the memory can only leak. Pair the allocation with
    a free (e.g. in `#finalize` or `#close`).
    TEXT

  GOOD_EXAMPLE = <<-CODE
    lib LibGeo
      fun malloc(size : Int32) : Void*
      fun free(ptr : Void*)
    end

    class Polygon
      def initialize
        @points = LibGeo.malloc(64)
      end

      def finalize
        LibGeo.free(@points) # paired with the malloc above
      end
    end
    CODE

  BAD_EXAMPLE = <<-CODE
    lib LibGeo
      fun malloc(size : Int32) : Void*
      fun free(ptr : Void*)
    end

    class Polygon
      def initialize
        @points = LibGeo.malloc(64) # LibGeo.free is never called — leak
      end
    end
    CODE

  DEFAULT_ALLOCATORS   = ["malloc", "calloc", "realloc", "xmalloc", "strdup"]
  DEFAULT_DEALLOCATORS = ["free", "xfree"]

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    allocators = config.strings("allocators", DEFAULT_ALLOCATORS)
    deallocators = config.strings("deallocators", DEFAULT_DEALLOCATORS)
    visitor = Visitor.new(source, allocators, deallocators)
    source.ast.try &.accept(visitor)
    visitor.report
    visitor.issues
  end

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    # {lib, fun, location, owner} of one allocating call.
    private alias AllocCall = {String, String, Crystal::Location?, String}

    def initialize(@source : Awesome::Source,
                   @allocators : Array(String),
                   @deallocators : Array(String))
      @libs = {} of String => Array(String) # lib name → declared fun names
      @alloc_calls = [] of AllocCall
      @freed_libs = Set(String).new # libs with ≥1 deallocator call
      @lib_stack = [] of String
      @def_stack = [] of String
    end

    def visit(node : Crystal::LibDef)
      # LibDef#name is a Path; key shims by its string form.
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

    def visit(node : Crystal::Def)
      @def_stack.push(node.name)
      node.body.accept(self)
      @def_stack.pop
      false
    end

    def visit(node : Crystal::Call)
      # Skip calls inside fun bodies (`fun x = ... end`): those define
      # the shim, they don't use it.
      return true unless @lib_stack.empty?

      if (obj = node.obj).is_a?(Crystal::Path)
        lib_name = obj.names.last
        if tracks?(lib_name)
          if @allocators.includes?(node.name)
            @alloc_calls << {lib_name, node.name, node.location, owner}
          elsif @deallocators.includes?(node.name)
            @freed_libs << lib_name
          end
        end
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    # A receiver is a tracked C shim when its lib is declared in this
    # file, or (for libs bound elsewhere, like stdlib's LibC) when it
    # follows the `Lib`-prefix naming convention.
    private def tracks?(name : String) : Bool
      @libs.has_key?(name) || name.starts_with?("Lib")
    end

    private def owner : String
      @def_stack.empty? ? "at top level" : "in `#{@def_stack.last}`"
    end

    def report : Nil
      @alloc_calls.each do |lib_name, fun_name, location, owner|
        next if @freed_libs.includes?(lib_name)
        @issues << Awesome::Issue.new(
          @source.path,
          "MemoryLeak",
          "`#{lib_name}.#{fun_name}` #{owner} allocates C heap memory, but " \
          "`#{lib_name}.#{@deallocators.first}` is never called in this file: " \
          "pair C allocations with a free (e.g. in `#finalize` or `#close`)",
          location,
          @source.excerpt_at(location.try(&.line_number) || 0)
        )
      end
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::MemoryLeak
