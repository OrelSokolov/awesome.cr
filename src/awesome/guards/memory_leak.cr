# MemoryLeak — C heap allocations from lib shims must be paired with a
# matching free somewhere in the project.
#
# `lib LibFoo ... fun malloc(...)` binds raw C allocators into Crystal.
# Memory they return lives on the C heap — the Crystal GC never frees
# it. The base check: every project that calls `LibFoo.malloc` (or any
# allocator fun) must also call `LibFoo.free` (or any deallocator fun)
# at least once. Zero free calls anywhere means the allocation can
# never be released — a certain leak, not a style nit.
#
# Project-wide (test_project): the pairing often spans files (a wrapper
# in one file, its cleanup in another), so alloc and free evidence is
# collected over all sources before anything is reported — a free in
# any file covers the allocation, and issues stay anchored to the
# alloc call site.
#
# No C parsing is needed: shims are `Crystal::LibDef` / `Crystal::FunDef`
# nodes and call sites are `Call`s with a `Path` receiver, so the guard
# works on the compiler's own AST. Libs not declared in the project
# (e.g. stdlib's `LibC`) are still tracked via the `Lib`-prefix naming
# convention; non-lib receivers (`Foo.malloc`) are never flagged.
class Awesome::Guards::MemoryLeak < Awesome::Guard
  KIND     = "memory"
  LEVEL    = "vibecoder" # a certain leak, not a style nit
  SEVERITY = "bug"       # runtime-breaker: the memory can only leak
  SHORT_DESCRIPTION = <<-TEXT
    Checks that C heap allocations from lib shims are paired with a
    matching free. `LibFoo.malloc` / `LibC.calloc` and friends return
    memory the Crystal GC will never release; if the project calls an
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
    [] of Awesome::Issue # evidence spans files — the project pass decides
  end

  def test_project(sources : Array(Awesome::Source), config : Awesome::GuardConfig) : Array(Awesome::Issue)
    allocators = config.strings("allocators", DEFAULT_ALLOCATORS)
    deallocators = config.strings("deallocators", DEFAULT_DEALLOCATORS)

    collectors = sources.map { |source| Collector.new(source).run(allocators, deallocators) }
    # A free anywhere in the project covers the allocation; a lib
    # declared in any file is tracked in all of them.
    freed = collectors.reduce(Set(String).new) { |acc, c| acc | c.free_libs }
    tracked = collectors.reduce(Set(String).new) { |acc, c| acc | c.declared_libs }

    issues = [] of Awesome::Issue
    collectors.flat_map(&.hits).each do |hit|
      next if freed.includes?(hit.lib)
      # Only C shims: declared somewhere in the project, or (for libs
      # bound elsewhere, like stdlib's LibC) the Lib-prefix convention.
      next unless tracked.includes?(hit.lib) || hit.lib.starts_with?("Lib")
      issues << Awesome::Issue.new(
        hit.source.path,
        "MemoryLeak",
        Awesome::I18n.t("guards.MemoryLeak.main",
          lib: hit.lib, fun: hit.fun, owner: hit.owner, free: deallocators.first),
        hit.location,
        hit.source.excerpt_at(hit.location.try(&.line_number) || 0)
      )
    end
    issues
  end

  # One allocating call site: lib name, fun name, location, enclosing
  # def (or "at top level"), and the source it was seen in (the project
  # pass spans files, an issue is anchored to one).
  private record Hit, lib : String, fun : String, location : Crystal::Location?,
    owner : String, source : Awesome::Source

  # One pass over a source: allocating/deallocating calls and declared
  # lib names, all recorded before the tracked/freed question is
  # decided — that needs the other files' evidence too.
  private class Collector < Crystal::Visitor
    getter hits = [] of Hit
    getter free_libs = Set(String).new
    getter declared_libs = Set(String).new

    @lib_stack = [] of String
    @def_stack = [] of String
    @allocators = [] of String
    @deallocators = [] of String

    def initialize(@source : Awesome::Source)
    end

    def run(allocators : Array(String), deallocators : Array(String)) : self
      @allocators = allocators
      @deallocators = deallocators
      @source.ast.try &.accept(self)
      self
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
        @declared_libs << @lib_stack.last
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
      # Skip calls inside lib bodies: fun definitions (`fun x = ...`)
      # define the shim, they don't use it.
      return true unless @lib_stack.empty?

      if (obj = node.obj).is_a?(Crystal::Path)
        lib_name = obj.names.last
        if @allocators.includes?(node.name)
          @hits << Hit.new(lib_name, node.name, node.location, owner, @source)
        elsif @deallocators.includes?(node.name)
          @free_libs << lib_name
        end
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    private def owner : String
      @def_stack.empty? ? "at top level" : "in `#{@def_stack.last}`"
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::MemoryLeak
