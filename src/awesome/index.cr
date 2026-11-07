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
#
# The entry type and the collecting visitor live beside this file, one
# class per file: index/type_entry.cr, index/visitor.cr.
class Awesome::Index
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
end
