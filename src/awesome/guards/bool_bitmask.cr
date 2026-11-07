# BoolBitmask — a pack of Bool fields is a poor man's bitmask.
#
# Rust's `bitflags` crate packs flags into one integer; in Crystal a
# `@[Flags]` enum does the same. Each `Bool` struct field costs a full
# byte, so four flags cost 4 bytes (plus they each grow the struct's
# footprint), while a `@[Flags]` enum costs 1. Fewer bytes also means
# cheaper copies and better cache density for arrays of such structs.
#
# Advisory: switching to a bitmask changes how the flags are read and
# written, so the guard only reports the saving and leaves the call to
# you. @[Extern] structs are skipped (their layout mirrors C).
class Awesome::Guards::BoolBitmask < Awesome::Guard
  KIND = "memory"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for structs with many Bool fields. Every Bool field costs a
    byte; a @[Flags] enum (Crystal's bitflags) packs the same flags into
    one. Fires when the count of Bool fields reaches min_bools
    (default 4). Advisory: converting to a bitmask changes how the flags
    are read and written. Structs with @[Extern] are skipped.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    @[Flags]
    enum Permissions
      Readable
      Writable
      Executable
      Sticky
    end

    struct Entry
      getter mode : Permissions  # 4 flags in 1 byte
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    struct Entry
      getter readable : Bool     # 4 flags = 4 bytes
      getter writable : Bool
      getter executable : Bool
      getter sticky : Bool
    end
  CODE

  FIELD_MACROS = {"property", "property?", "getter", "getter?"}

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    min_bools = config.int("min_bools", 4)
    visitor = Visitor.new(source, min_bools)
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    def initialize(@source : Awesome::Source, @min_bools : Int32)
      @annotations = {} of UInt64 => Array(String)
    end

    def visit(node : Crystal::Expressions)
      exprs = node.expressions
      exprs.each_with_index do |e, i|
        next unless e.is_a?(Crystal::Annotation)
        nxt = exprs[i + 1]?
        next unless nxt.is_a?(Crystal::ClassDef)
        (@annotations[nxt.object_id] ||= [] of String) << e.path.to_s
      end
      true
    end

    def visit(node : Crystal::ClassDef)
      check(node) if node.struct?
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    private def check(node : Crystal::ClassDef)
      anns = @annotations[node.object_id]? || [] of String
      return if anns.includes?("Extern")

      bools = [] of String
      each_field_type(node.body) do |name, type|
        bools << name if bool_type?(type)
      end
      return unless bools.size >= @min_bools

      @issues << Awesome::Issue.new(
        @source.path,
        "BoolBitmask",
        Awesome::I18n.t("guards.BoolBitmask.main",
          count: bools.size, first: bools.first.capitalize, last: bools.last.capitalize),
        node.location,
        @source.excerpt_at(node.location.try(&.line_number) || 0)
      )
    end

    private def bool_type?(type : Crystal::ASTNode) : Bool
      type.is_a?(Crystal::Path) && type.names.size == 1 && type.names.first == "Bool"
    end

    # Yields {name, type node} for every declared instance variable:
    # `@x : T` TypeDeclarations and `property/property?/getter/getter?`
    # macro calls (as parsed, unexpanded).
    private def each_field_type(body)
      nodes = body.is_a?(Crystal::Expressions) ? body.expressions : [body] of Crystal::ASTNode
      nodes.each do |n|
        case n
        when Crystal::TypeDeclaration
          var = n.var
          next unless var.is_a?(Crystal::InstanceVar) || var.is_a?(Crystal::Var)
          yield({var.to_s, n.declared_type})
        when Crystal::Call
          next unless FIELD_MACROS.includes?(n.name)
          n.args.each do |arg|
            next unless arg.is_a?(Crystal::TypeDeclaration)
            var = arg.var
            next unless var.is_a?(Crystal::InstanceVar) || var.is_a?(Crystal::Var)
            yield({var.to_s, arg.declared_type})
          end
        end
      end
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::BoolBitmask
