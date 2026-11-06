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
#
# Reopenings merge: a type written as `class Foo` in several files is
# one entry whose def lists span all of them (the first declaration
# keeps origin/superclass/decl), so per-project guards see the whole
# type, not the last fragment of it.
class Awesome::Index
  # One indexed type (class, struct or module) as written.
  class TypeEntry
    # Where the type was written — path and location always travel
    # together (bundled so the constructor stays under LongParameterList).
    record Origin, path : String, location : Crystal::Location?

    getter qualified_name : String # nesting stack + written name
    # Superclass path as written (a Generic parent stripped to its
    # name, leading `::` dropped); nil for Object / no parent / modules.
    getter superclass : String?
    # Module names as written in `include` clauses (`include Store`
    # records "Store") — the module half of an abstraction seam, next
    # to `superclass` for the class half.
    getter included_modules : Array(String)
    getter def_names : Array(String)
    # Names of `abstract def`s — contracts to be overridden, distinct
    # from concrete defs (guards that compare implementations exclude
    # these; SubclassNoOverride keeps counting them).
    getter abstract_def_names : Array(String)
    getter origin : Origin
    # The ClassDef/ModuleDef the type was declared with — kept as
    # written, so guards can ask how it was declared (abstract, module,
    # struct) without duplicating that in flags here. For a reopened
    # type this is the first declaration (reopenings can't change how a
    # type was declared).
    getter decl : Crystal::ClassDef | Crystal::ModuleDef

    def initialize(@qualified_name : String, @superclass : String?,
                   @decl : Crystal::ClassDef | Crystal::ModuleDef,
                   @included_modules : Array(String),
                   @def_names : Array(String),
                   @abstract_def_names : Array(String), @origin : Origin)
    end

    def abstract? : Bool
      decl = @decl
      decl.is_a?(Crystal::ClassDef) && decl.abstract?
    end

    def module? : Bool
      @decl.is_a?(Crystal::ModuleDef)
    end

    # Value types carry data, not collaborators — a `struct Foo` entry
    # is data plumbing, not a dependency candidate.
    def struct? : Bool
      decl = @decl
      decl.is_a?(Crystal::ClassDef) && decl.struct?
    end

    def last_segment : String
      @qualified_name.split("::").last
    end

    def path : String
      @origin.path
    end

    def location : Crystal::Location?
      @origin.location
    end

    def line : Int32
      location.try(&.line_number) || 0
    end

    # Folds a reopening into this entry: def names merge (a method list
    # spanning files is one list), while the first declaration keeps
    # origin, superclass and decl — a reopening can't change those
    # (the compiler rejects a superclass mismatch).
    def merge_reopening!(other : TypeEntry) : Nil
      other.def_names.each do |name|
        @def_names << name unless @def_names.includes?(name)
      end
      other.abstract_def_names.each do |name|
        @abstract_def_names << name unless @abstract_def_names.includes?(name)
      end
      other.included_modules.each do |name|
        @included_modules << name unless @included_modules.includes?(name)
      end
      @superclass ||= other.superclass
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

  # Called by the visitor while walking the sources. A reopening of an
  # already indexed type (same qualified name, another file or later in
  # the same file) folds into the existing entry instead of adding a
  # second one — def lists merge, the first declaration keeps origin,
  # superclass and decl. Returns the canonical entry (the surviving
  # one), so the visitor attaches later defs to it, not to the discarded
  # reopening.
  def add(entry : TypeEntry) : TypeEntry
    if existing = @by_name[entry.qualified_name]?
      existing.merge_reopening!(entry)
      return existing
    end
    @entries << entry
    @by_name[entry.qualified_name] = entry
    (@by_last_segment[entry.last_segment] ||= [] of TypeEntry) << entry
    entry
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

  # Concrete implementations of an abstraction within the project: the
  # direct subclasses of a class, or the entries `include`-ing a module.
  # An abstraction with two or more of these is a seam the project
  # already declared — guards take that as evidence, not a guess.
  def implementations_of(entry : TypeEntry) : Array(TypeEntry)
    if entry.module?
      @entries.select do |e|
        e.included_modules.any? do |name|
          resolve(name).try(&.qualified_name) == entry.qualified_name
        end
      end
    else
      subclasses_of(entry)
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
      push(node, superclass_of(node))
      true
    end

    def visit(node : Crystal::ModuleDef)
      push(node, nil)
      true
    end

    def visit(node : Crystal::Include)
      @nesting.last?.try { |entry| entry.included_modules << node.name.to_s }
      true
    end

    def end_visit(node : Crystal::ClassDef | Crystal::ModuleDef)
      @nesting.pop
    end

    def visit(node : Crystal::Def)
      if entry = @nesting.last?
        entry.def_names << node.name
        entry.abstract_def_names << node.name if node.abstract?
      end
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end

    private def push(node : Crystal::ClassDef | Crystal::ModuleDef,
                     superclass : String?) : Nil
      names = @nesting.map(&.qualified_name) << node.name.to_s
      entry = TypeEntry.new(names.join("::"), superclass, node,
        [] of String, [] of String, [] of String,
        TypeEntry::Origin.new(@path, node.location))
      # add() folds a reopening into the canonical entry and hands it
      # back — defs written in this reopening attach to that one.
      @nesting << @index.add(entry)
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
