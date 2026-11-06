# Syntactic project index for per-project guards (`Guard#test_project`):
# the type hierarchy as written, gathered in one pass over the already
# collected sources — no semantic resolution.
#
# The index sees exactly the files guards see (Runner's collected set —
# config excludes apply, `lib/**` is excluded by default), so it covers
# the current project only: a superclass not found in the index is
# external (a shard or the stdlib), and per-project guards treat that as
# a cut-off point instead of guessing.
#
# Name resolution is honest about being syntactic: `class B < Base`
# inside `module Foo` may mean `Foo::Base` or the top-level `Base`, and
# the parser can't tell. `resolve` first tries an exact qualified-name
# match, then falls back to a unique candidate by last path segment;
# zero or several candidates → nil — ambiguity means "can't tell", and
# guards skip what they can't tell (better a false negative than a
# false positive).
class Awesome::Index
  # One indexed type (class, struct or module) as written.
  class TypeEntry
    getter qualified_name : String # nesting stack + written name
    # Superclass path as written (a Generic parent stripped to its
    # name, leading `::` dropped); nil for Object / no parent / modules.
    getter superclass : String?
    getter def_names : Array(String)
    getter path : String
    getter location : Crystal::Location?

    def initialize(@qualified_name : String, @superclass : String?, @is_abstract : Bool,
                   @is_module : Bool, @def_names : Array(String), @path : String,
                   @location : Crystal::Location?)
    end

    def last_segment : String
      @qualified_name.split("::").last
    end

    def abstract? : Bool
      @is_abstract
    end

    def module? : Bool
      @is_module
    end

    def line : Int32
      @location.try(&.line_number) || 0
    end
  end

  getter entries : Array(TypeEntry)

  @by_name : Hash(String, TypeEntry)
  @by_last_segment : Hash(String, Array(TypeEntry))

  def initialize(sources : Array(Awesome::Source))
    @entries = [] of TypeEntry
    @by_name = {} of String => TypeEntry
    @by_last_segment = {} of String => Array(TypeEntry)
    sources.each do |source|
      source.ast.try &.accept(Visitor.new(self, source.path))
    end
  end

  # Called by the visitor while walking the sources.
  def add(entry : TypeEntry) : Nil
    @entries << entry
    @by_name[entry.qualified_name] = entry
    (@by_last_segment[entry.last_segment] ||= [] of TypeEntry) << entry
  end

  # Exact qualified-name match ("App::Base" as written in the sources).
  def find(qualified_name : String) : TypeEntry?
    @by_name[qualified_name]?
  end

  # All entries whose qualified name ends in this segment — for a
  # superclass written as a relative path ("Base" vs "App::Base").
  def by_last_segment(segment : String) : Array(TypeEntry)
    @by_last_segment[segment]? || [] of TypeEntry
  end

  # Resolve a written path (a superclass) to an indexed type: exact
  # qualified match first, then a unique last-segment candidate. Nil on
  # zero or ambiguous candidates — or an external type.
  def resolve(path : String) : TypeEntry?
    path = path.lchop("::")
    find(path) || begin
      candidates = by_last_segment(path.split("::").last)
      candidates.size == 1 ? candidates.first : nil
    end
  end

  # Direct subclasses of an indexed type within the project (each
  # entry's written superclass resolved back to it).
  def subclasses_of(entry : TypeEntry) : Array(TypeEntry)
    @entries.select do |e|
      next false unless parent = e.superclass
      resolve(parent).try(&.qualified_name) == entry.qualified_name
    end
  end

  # Walks one source, registering a TypeEntry per ClassDef/ModuleDef
  # with the file's naming stack as its qualified name, and attaching
  # def names (regular and `abstract def`) to the innermost type.
  private class Visitor < Crystal::Visitor
    @nesting = [] of TypeEntry # innermost type last

    def initialize(@index : Index, @path : String)
    end

    def visit(node : Crystal::ClassDef)
      push(node, superclass_of(node), node.abstract?)
      true
    end

    def visit(node : Crystal::ModuleDef)
      push(node, nil, false)
      true
    end

    def end_visit(node : Crystal::ClassDef | Crystal::ModuleDef)
      @nesting.pop
    end

    def visit(node : Crystal::Def)
      if entry = @nesting.last?
        entry.def_names << node.name
      end
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end

    private def push(node : Crystal::ClassDef | Crystal::ModuleDef,
                     superclass : String?, is_abstract : Bool) : Nil
      names = @nesting.map(&.qualified_name) << node.name.to_s
      entry = TypeEntry.new(names.join("::"), superclass, is_abstract,
        node.is_a?(Crystal::ModuleDef), [] of String, @path, node.location)
      @index.add(entry)
      @nesting << entry
    end

    # Superclass path as a plain string: `Base(T)` keeps only `Base` —
    # type vars never matter for hierarchy checks.
    private def superclass_of(node : Crystal::ClassDef) : String?
      case parent = node.superclass
      when Crystal::Generic then parent.name.to_s.lchop("::")
      when Crystal::Path    then parent.to_s.lchop("::")
      else                       parent.try &.to_s
      end
    end
  end
end
