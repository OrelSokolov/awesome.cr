# NilableStructField — nilable fields inside structs are expensive.
#
# Rust's `Option<i64>` is niche-optimized down to 8 bytes; Crystal has
# no niche optimization, so `Int64?` is a tagged union
# `{Int32 type_id, Int64 value}` — 16 bytes (with padding) and a branch
# on every access. On hot structs a sentinel value ("impossible" value
# of the payload type) or a separate Bool flag keeps the field at its
# natural size and the access branch-free.
#
# Conservative by design: the guard only fires when every non-nil union
# member is a builtin type, so the byte cost stated in the message is
# always exact. @[Extern] structs are skipped (their layout mirrors C).
class Awesome::Guards::NilableStructField < Awesome::Guard
  KIND = "memory"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for nilable fields (`Int64?`, `String | Nil`) inside structs.
    A nilable field is a tagged union — `{Int32 tag, payload}` — so it
    costs more than the payload alone (`Int64?` is 16 bytes, not 8) and
    adds a branch on every access. Rust's niche optimization does not
    exist in Crystal; prefer a sentinel value or a separate Bool flag.
    Structs with @[Extern] are skipped.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    struct Session
      getter id : Int64       # absent sessions use ID 0
      getter closed : Bool    # explicit state instead of nil
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    struct Session
      getter id : Int64?      # 16 bytes + a branch, not 8
      getter closed : Bool
    end
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

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    def initialize(@source : Awesome::Source)
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
      return if anns.includes?("Extern")

      each_field_type(node.body) do |name, type|
        next unless type.is_a?(Crystal::Union)
        members = type.types
        next unless members.any? { |m| m.is_a?(Crystal::Path) && {"Nil", "::Nil"}.includes?(m.to_s) }

        layout = nilable_layout(members)
        next unless layout # unprovable member — skip the field
        nilable_size, payload_size = layout

        @issues << Awesome::Issue.new(
          @source.path,
          "NilableStructField",
          Awesome::I18n.t("guards.NilableStructField.main",
            field: name, size: nilable_size, payload: payload_size),
          type.location,
          @source.excerpt_at(type.location.try(&.line_number) || 0)
        )
      end
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

    # {nilable union size, plain payload size} of a union containing Nil,
    # or nil when a non-nil member is not a provable builtin. The union
    # layout is `{Int32 tag, payload}` with the payload aligned to its
    # natural alignment (C ABI rules).
    private def nilable_layout(members : Array(Crystal::ASTNode)) : {Int32, Int32}?
      align = 4
      payload = 0
      members.each do |m|
        next if m.is_a?(Crystal::Path) && {"Nil", "::Nil"}.includes?(m.to_s)
        return nil unless m.is_a?(Crystal::Path) && m.names.size == 1
        layout = PRIMITIVES[m.names.first]?
        return nil unless layout
        align = {align, layout[0]}.max
        payload = {payload, layout[1]}.max
      end
      return nil if payload == 0 # `Nil` alone — not a nilable field

      offset = (4 + align - 1) // align * align # padding after the tag
      size = offset + payload
      size = (size + align - 1) // align * align
      {size, payload}
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::NilableStructField
