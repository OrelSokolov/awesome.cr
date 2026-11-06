# ToSWithoutIo — a zero-arg `to_s` override nobody calls.
#
# `io << obj`, string interpolation and `puts obj` all funnel through
# `to_s(io : IO)` — the zero-arg `Object#to_s` is just a wrapper that
# calls `to_s(io)` and materializes a String (Crystal 1.21:
# interpolation expands to `String.interpolation`, which writes via
# `to_s(io)`). Overriding the wrapper changes neither the IO path nor
# interpolation: every caller keeps the default representation, and
# whoever calls `obj.to_s` directly pays for a fresh String. Define
# `def to_s(io : IO)` and write into the io instead.
#
# Skipped when the class also defines a `to_s` overload with arguments
# (`def to_s(io : IO)`) anywhere in the project — such an overload
# usually delegates to the zero-arg form, so "never runs where it
# matters" would be a false positive. Project-wide (`test_project`)
# because the overload may live in another file (a reopened class).
#
# Gated by `check_to_s` (default true) — a separately switchable
# pattern: some codebases deliberately keep a zero-arg to_s as API.
class Awesome::Guards::ToSWithoutIo < Awesome::Guard
  KIND = "memory"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for `def to_s` without arguments. `io << obj`, string
    interpolation and `puts obj` all call `to_s(io : IO)`, so a
    zero-arg to_s override never runs on those paths — and every
    direct caller allocates a String. Define `def to_s(io : IO)` and
    write into the io instead. Skipped when the class also defines a
    to_s overload with arguments anywhere in the project. Switch off
    with check_to_s: false if the zero-arg form is deliberate API.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    def to_s(io : IO)
      io << @name << '#' << @id   # feeds io <<, interpolation, puts
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    def to_s
      "\#{@name} \#{@id}"   # io << obj still prints the default
    end
  CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    [] of Awesome::Issue # evidence spans files — the project pass decides
  end

  def test_project(sources : Array(Awesome::Source), config : Awesome::GuardConfig) : Array(Awesome::Issue)
    return [] of Awesome::Issue unless config.bool("check_to_s", true)

    zero_arg = [] of ZeroArgDef
    io_overload_owners = Set(String).new

    sources.each do |source|
      visitor = Visitor.new(source)
      source.ast.try &.accept(visitor)
      zero_arg.concat(visitor.zero_arg_defs)
      io_overload_owners.concat(visitor.io_overload_owners)
    end

    zero_arg.reject { |d| io_overload_owners.includes?(d.owner) }.map do |d|
      Awesome::Issue.new(
        d.source.path,
        "ToSWithoutIo",
        "def to_s without an IO argument never runs where it matters: io <<, " \
        "interpolation and puts all call to_s(io : IO) — define " \
        "`def to_s(io : IO)` and write into the io instead",
        d.location,
        d.source.excerpt_at(d.line)
      )
    end
  end

  # One zero-arg `def to_s`: its enclosing type (qualified name, "" for
  # top-level defs), location, and the source it lives in.
  private record ZeroArgDef, owner : String, location : Crystal::Location?,
    source : Awesome::Source do
    def line : Int32
      @location.try(&.line_number) || 0
    end
  end

  private class Visitor < Crystal::Visitor
    getter zero_arg_defs = [] of ZeroArgDef
    getter io_overload_owners = Set(String).new

    @nesting = [] of String # enclosing type names, innermost last

    def initialize(@source : Awesome::Source)
    end

    def visit(node : Crystal::ClassDef | Crystal::ModuleDef)
      @nesting << node.name.to_s
      true
    end

    def end_visit(node : Crystal::ClassDef | Crystal::ModuleDef)
      @nesting.pop
    end

    def visit(node : Crystal::Def)
      if node.name == "to_s"
        owner = @nesting.join("::")
        if node.args.empty? && node.block_arg.nil?
          zero_arg_defs << ZeroArgDef.new(owner, node.location, @source)
        else
          io_overload_owners << owner
        end
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::ToSWithoutIo
