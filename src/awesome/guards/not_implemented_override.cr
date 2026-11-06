# NotImplementedOverride — a subclass that breaks its parent's promise.
#
# When a parent's method is concrete (it works), overriding it with a
# body that only raises NotImplementedError doesn't specialize — it
# revokes. Through the parent's interface the subclass claims to do
# what the parent does, then refuses at runtime: the exact "can't
# stand where the parent stood" Liskov talks about. Either the
# behaviour doesn't apply to this variant (then it shouldn't inherit
# it — compose instead), or the method is actually a contract (then
# the parent should declare `abstract def` and let the compiler
# demand implementations).
#
# Project-wide (`test_project`): the parent usually lives in another
# file, so raise-only defs are paired with parents from the
# syntactic Index. A raise-only def matching only the parent's
# `abstract def` is skipped — implementing a contract with a raise is
# a compiler/coverage problem, not a broken promise.
class Awesome::Guards::NotImplementedOverride < Awesome::Guard
  KIND = "smell"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for a subclass method whose whole body is
    `raise NotImplementedError.new(...)`, overriding a parent's
    concrete method of the same name — the subclass accepts the
    parent's interface and then refuses it (LSP). External parents
    and matches against abstract defs are skipped.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    class Shape
      def area
        compute_area # works for every shape that inherits it
      end
    end

    class Circle < Shape
      def area # specializes — the promise holds
        Math::PI * @radius ** 2
      end
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    class Shape
      def area # concrete — a promise to every caller
        compute_area
      end
    end

    class Line < Shape
      def area # revokes the promise at runtime
        raise NotImplementedError.new("lines have no area")
      end
    end
  CODE

  def test_project(sources : Array(Awesome::Source), config : Awesome::GuardConfig) : Array(Awesome::Issue)
    index = Awesome::Index.new(sources)
    by_path = sources.map { |s| {s.path, s} }.to_h

    issues = [] of Awesome::Issue
    sources.each do |source|
      visitor = RaiseDefsVisitor.new
      source.ast.try &.accept(visitor)

      visitor.raise_defs.each do |raise_def|
        next unless entry = index.find(raise_def.owner)
        next if entry.module?
        next unless parent_path = entry.superclass
        next unless parent = index.resolve(parent_path)
        next if parent.qualified_name == entry.qualified_name

        next unless parent.def_names.includes?(raise_def.method_name)
        next if parent.abstract_def_names.includes?(raise_def.method_name)

        issues << Awesome::Issue.new(
          source.path,
          "NotImplementedOverride",
          "#{entry.qualified_name}##{raise_def.method_name} only raises " \
          "NotImplementedError but #{parent.qualified_name}#" \
          "#{raise_def.method_name} is concrete — the subclass can't stand " \
          "where the parent stood; keep the behaviour, don't inherit, or " \
          "declare it abstract in the parent",
          raise_def.location,
          source.excerpt_at(raise_def.line)
        )
      end
    end
    issues
  end

  record RaiseDef, owner : String, method_name : String, location : Crystal::Location? do
    def line : Int32
      @location.try(&.line_number) || 0
    end
  end

  # Collects defs whose whole body is `raise NotImplementedError.new(...)`
  # (any message), with the enclosing type's qualified name. Bare
  # `raise "..."` with a String doesn't count — only the type itself
  # says "not implemented".
  private class RaiseDefsVisitor < Crystal::Visitor
    getter raise_defs = [] of RaiseDef

    @nesting = [] of String

    def initialize
    end

    def visit(node : Crystal::ClassDef | Crystal::ModuleDef)
      @nesting << node.name.to_s
      true
    end

    def end_visit(node : Crystal::ClassDef | Crystal::ModuleDef)
      @nesting.pop
    end

    def visit(node : Crystal::Def)
      if not_implemented_raise?(node.body)
        owner = @nesting.empty? ? "" : @nesting.join("::")
        raise_defs << RaiseDef.new(owner, node.name, node.location) unless owner.empty?
      end
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end

    private def not_implemented_raise?(body : Crystal::ASTNode?) : Bool
      return false unless body.is_a?(Crystal::Call) && body.name == "raise"
      return false unless body.args.size == 1

      case arg = body.args.first
      when Crystal::Call
        obj = arg.obj
        arg.name == "new" && obj.is_a?(Crystal::Path) && obj.to_s == "NotImplementedError"
      else
        false
      end
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::NotImplementedOverride
