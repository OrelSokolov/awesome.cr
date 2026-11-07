# One indexed type (class, struct or module) as written — see
# Awesome::Index for the index itself.
class Awesome::Index::TypeEntry
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
