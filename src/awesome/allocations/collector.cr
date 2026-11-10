# One pass over a source: where the allocations sit and what is
# called. Records three things (all line-anchored, the analyzer turns
# them into statuses):
#
#   direct_red — lines holding an allocation construct;
#   calls      — call sites that need their target resolved (every
#                call that is not an allocation construct and not a
#                pure builtin — including `puts`, operators, macro
#                calls: anything whose body the scope may or may not
#                know);
#   defs       — def/fun containers with their line spans.
#
# What counts as an allocation construct (conservative, name-based —
# no type inference, so red means "allocates or may allocate"):
#
#   `new` on anything (class or struct — the syntax cannot tell, and
#   a heap-held struct still allocates);
#   known allocating method names: copy/build pass(es) over
#   collections (`map`, `select`, `compact`, `sort`, …), String
#   builders (`gsub`, `split`, `capitalize`, `join`, …);
#   `to_s` with no arguments (the io-less overload builds a String);
#   C allocators called on a constant path: `LibX.malloc`,
#   `Pointer.malloc` (fun names from the lib-shim world);
#   String interpolation (each evaluation builds a String), Array and
#   Hash literals (a fresh one per evaluation), Regex literals.
#
# Deliberately NOT allocation constructs: String literals (deduped
# into static data by the compiler — the interpolation, not the
# literal, is what allocates), tuples and named tuples (stack), range
# literals (structs), `is_a?`/`as`/`responds_to?` (not even Call nodes
# — the compiler has dedicated AST nodes for them).
class Awesome::Allocations::Collector < Crystal::Visitor
  # Calls that allocate on any receiver they are defined on. Left
  # deliberately wide: `xs.first(n)`/`String#+` and friends need
  # receiver types to be precise, and the report is conservative by
  # design (a false red is a re-check, a false green is a lie).
  ALLOCATING_CALLS = %w[
    new dup clone
    map map_with_index flat_map compact_map select reject compact
    flatten uniq sort sort_by shuffle reverse rotate group_by
    partition zip tally each_slice each_cons
    split chars lines bytes words join build sprintf format
    capitalize downcase upcase titleize underscore camelcase
    chomp chop strip lstrip rstrip squeeze tr tr_s sub gsub delete succ
    gets read_line read_all
  ]

  # C-heap allocators: red when called on a constant path —
  # `LibGeo.malloc`, `Pointer.malloc` (and a user's `Buf.malloc`
  # reads as an allocator too, close enough for a report).
  LIB_ALLOCATORS = %w[malloc calloc realloc xmalloc strdup]

  # Pure on every possible receiver — compiler-level queries. Calling
  # one never allocates, so these never even become call sites.
  PURE_CALLS = %w[nil? itself object_id class]

  getter source : Awesome::Source
  getter defs = [] of Awesome::Allocations::DefInfo
  getter direct_red = Set(Int32).new
  getter calls = [] of Awesome::Allocations::CallSite
  # Filled by the Analyzer once the scope's call graph is known.
  property statuses = [] of Awesome::Allocations::Status
  property? parsable = false

  def initialize(@source : Awesome::Source)
    if ast = @source.ast
      @parsable = true
      ast.accept(self)
    end
  end

  def visit(node : Crystal::Def) : Bool
    record_def(node.name, node, resolvable: true)
    node.body.accept(self)
    false
  end

  # A `fun` body is runtime code (called back from C), so its marks
  # count — but no Crystal call site can name it, so it never
  # resolves as a target.
  def visit(node : Crystal::FunDef) : Bool
    if body = node.body
      record_def("fun:#{node.name}", node, resolvable: false)
      body.accept(self)
    end
    false
  end

  # A macro body is expansion-time text, not runtime lines — skip it
  # entirely (macro *calls* are ordinary call sites and go gray).
  def visit(node : Crystal::Macro) : Bool
    false
  end

  def visit(node : Crystal::Call) : Bool
    if allocating?(node)
      mark_red(node)
    elsif !PURE_CALLS.includes?(node.name)
      @calls << Awesome::Allocations::CallSite.new(line_of(node), node.name)
    end
    true # args and blocks carry their own marks
  end

  def visit(node : Crystal::StringInterpolation) : Bool
    mark_red(node)
    true # the interpolated expressions may hold calls of their own
  end

  def visit(node : Crystal::ArrayLiteral) : Bool
    mark_red(node)
    true
  end

  def visit(node : Crystal::HashLiteral) : Bool
    mark_red(node)
    true
  end

  def visit(node : Crystal::RegexLiteral) : Bool
    mark_red(node) # compiles a fresh Regex per evaluation
    true
  end

  def visit(node : Crystal::ASTNode) : Bool
    true
  end

  private def allocating?(node : Crystal::Call) : Bool
    return true if ALLOCATING_CALLS.includes?(node.name)
    return true if node.name == "to_s" && node.args.empty?
    node.obj.is_a?(Crystal::Path) && LIB_ALLOCATORS.includes?(node.name)
  end

  private def record_def(name : String, node : Crystal::ASTNode, resolvable : Bool) : Nil
    start = line_of(node)
    end_line = node.end_location.try(&.line_number) || @source.code_lines.size
    @defs << Awesome::Allocations::DefInfo.new(name, start, start, end_line, resolvable)
  end

  private def mark_red(node : Crystal::ASTNode) : Nil
    @direct_red << line_of(node)
  end

  private def line_of(node : Crystal::ASTNode) : Int32
    node.location.try(&.line_number) || 1
  end
end
