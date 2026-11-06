# StructurePacking — struct fields must go from the widest alignment to
# the narrowest, so the struct wastes no bytes on padding.
#
# Crystal lays struct fields out in declaration order with each field
# aligned to its natural alignment (C ABI rules) — the compiler never
# reorders them. A struct declared as `UInt8, Int64, UInt8` takes 24
# bytes; the same fields ordered `Int64, UInt8, UInt8` take 16. Less
# memory, fewer cache misses — a free win on hot structs (especially on
# ARM, where NEON also dislikes sparse data).
#
# Conservative by design: structs with any field whose layout cannot be
# proven from builtin types alone (custom structs, enums, ...) are
# skipped, so the guard never fires a false positive.
class Awesome::Guards::StructurePacking < Awesome::Guard
  KIND = "memory"
  SHORT_DESCRIPTION = <<-TEXT
    Checks that struct fields are ordered by decreasing alignment so the
    struct wastes no bytes on padding. Crystal lays fields out in
    declaration order following C ABI rules and never reorders them, so
    `UInt8, Int64, UInt8` costs 24 bytes while `Int64, UInt8, UInt8`
    costs 16. Structs with `@[Packed]` / `@[Alignment]` and (by default)
    `@[Extern]` ones are skipped.
    TEXT

  GOOD_EXAMPLE = <<-CODE
    struct Pixel
      getter value : Int64     # widest first
      getter red : Int32
      getter green : UInt8
      getter blue : UInt8
    end
    # sizeof == 16, no padding
    CODE

  BAD_EXAMPLE = <<-CODE
    struct Pixel
      getter red : UInt8       # narrow first…
      getter value : Int64     # …forces padding around the Int64
      getter green : UInt8
      getter blue : UInt8
    end
    # sizeof == 24 (8 bytes of padding) — should be 16
    CODE

  FIELD_MACROS = {"property", "property?", "getter", "getter?"}

  # Natural (alignment, size) of builtin types on all supported targets.
  PRIMITIVES = {
    "Bool":    {1, 1},
    "UInt8":   {1, 1}, "Int8": {1, 1},
    "UInt16":  {2, 2}, "Int16": {2, 2},
    "UInt32":  {4, 4}, "Int32": {4, 4}, "Float32": {4, 4},
    "Char":    {4, 4}, "Symbol": {4, 4},
    "UInt64":  {8, 8}, "Int64": {8, 8}, "Float64": {8, 8},
    "String":  {8, 8}, # reference, pointer-sized
  }

  # Generic types that are known references (pointer-sized).
  REFERENCE_GENERICS = {"Array", "Hash", "Slice", "Deque", "Proc"}

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    check_extern = config.bool("check_extern", false)
    visitor = Visitor.new(source, check_extern)
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  # {name, alignment, size} of one field.
  private alias Field = {String, Int32, Int32}

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    def initialize(@source : Awesome::Source, @check_extern : Bool)
      # Annotations parsed by the compiler sit as siblings preceding the
      # ClassDef inside the enclosing Expressions, so pair them up.
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
      return if anns.any? { |a| {"Packed", "Alignment"}.includes?(a) }
      return if anns.includes?("Extern") && !@check_extern

      fields = collect_fields(node.body)
      return unless fields && fields.size > 1

      current = sizeof_layout(fields)
      optimal = sizeof_layout(sorted_by_alignment(fields))
      return unless optimal < current

      @issues << Awesome::Issue.new(
        @source.path,
        "StructurePacking",
        "Reorder struct fields by decreasing alignment " \
        "(largest first): sizeof can shrink from #{current} to #{optimal} bytes",
        node.location,
        @source.excerpt_at(node.location.try(&.line_number) || 0)
      )
    end

    private def collect_fields(body) : Array(Field)?
      fields = [] of Field
      names = Set(String).new

      each_field_node(body) do |node|
        name, type = node
        layout = layout_of(type)
        return nil unless layout # unprovable field type — skip the struct
        next if names.includes?(name)
        names << name
        fields << {name, layout[0], layout[1]}
      end

      fields.size > 1 ? fields : nil
    end

    # Yields {name, type node} for every declared instance variable:
    # `@x : T` TypeDeclarations and `property/property?/getter/getter? x : T`
    # macro calls (as parsed, unexpanded). Returns false-ish (nil) from the
    # enclosing collect_fields when a field has no provable declaration.
    private def each_field_node(body)
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
          # `getter x` without a type declaration: layout unprovable.
          return_flag = n.args.any? { |a| !a.is_a?(Crystal::TypeDeclaration) }
          yield({"", Crystal::Path.new("unprovable")}) if return_flag
        when Crystal::Assign
          # `@x = ...` without a type declaration: layout unprovable.
          if n.target.is_a?(Crystal::InstanceVar) && !n.value.is_a?(Crystal::TypeDeclaration)
            yield({n.target.to_s, Crystal::Path.new("unprovable")})
          end
        end
      end
    end

    # {alignment, size} of a type node, or nil when it cannot be proven
    # from builtin types alone (custom structs, enums, ...).
    private alias Layout = {Int32, Int32}

    private def layout_of(type : Crystal::ASTNode) : Layout?
      case type
      when Crystal::Path
        return nil unless type.names.size == 1
        name = type.names.first
        return nil if name == "unprovable" # sentinel, see each_field_node
        PRIMITIVES[name]?
      when Crystal::Generic
        case path_string(type)
        when "Pointer"            then {8, 8}
        when .starts_with?("StaticArray")
          static_array_layout(type)
        else
          name = path_string(type)
          REFERENCE_GENERICS.includes?(name) ? {8, 8} : nil
        end
      when Crystal::Union
        union_layout(type.types)
      else
        nil
      end
    end

    private def static_array_layout(g : Crystal::Generic) : Layout?
      t, n = g.type_vars
      inner = layout_of(t).as(Layout?)
      count = n.to_s.to_i?
      return nil unless inner && count
      {inner[0], inner[1] * count}
    end

    private def union_layout(types : Array(Crystal::ASTNode)) : Layout?
      layouts = types.map { |t| layout_of(t).as(Layout?) }
      return nil if layouts.any?(&.nil?)
      align = 1
      size = 0
      layouts.each do |l|
        a, s = l.not_nil!
        align = {align, a}.max
        size = {size, s}.max
      end
      {align, size}
    end

    private def path_string(g : Crystal::Generic) : String
      name = g.name
      name.responds_to?(:names) ? name.names.join("::") : name.to_s
    end

    private def sorted_by_alignment(fields : Array(Field)) : Array(Field)
      fields.map_with_index { |f, i| {f, i} }
        .sort_by { |(f, i)| {-f[1], i} } # stable: widest first, keep order
        .map &.[0]
    end

    private def sizeof_layout(fields : Array(Field)) : Int32
      offset = 0
      max_align = 1
      fields.each do |(_, align, size)|
        offset = (offset + align - 1) // align * align
        offset += size
        max_align = {max_align, align}.max
      end
      (offset + max_align - 1) // max_align * max_align
    end
  end
end


Awesome::Guard.registered << Awesome::Guards::StructurePacking
