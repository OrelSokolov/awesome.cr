# UtilityClass — a namespace pretending to be a class.
#
# A class whose methods are all `def self.` and that declares no
# instance behaviour (no initialize, no instance defs, no field
# macros) is never usefully instantiated: it is a bag of names, i.e. a
# namespace — Crystal's spelling for that is `module`. The switch is
# free: every `Klass.method` call site stays valid, only meaningless
# `Klass.new` would break, and there is nothing to instantiate.
#
# The guard fires only on provable emptiness: one instance def, one
# initialize, one getter/property, or one instance macro means the
# class has instance behaviour and is skipped. A superclass also
# exempts the class — inherited behaviour is unknowable from syntax —
# and so does a `def self.new` factory (construction through it is
# meaningful, and a module can't take its place).
class Awesome::Guards::UtilityClass < Awesome::Guard
  KIND = "smell"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for classes that are namespaces in disguise: every method
    is `def self.`, with no initialize, no instance defs and no field
    macros — never usefully instantiated. A module says the same and
    keeps every call site valid. Classes with a superclass or any
    instance behaviour are skipped.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    module Registry           # a namespace, honestly
      def self.load(path)
      end
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    class Registry            # never instantiated — a module in disguise
      def self.load(path)
      end

      def self.save(path, data)
      end
    end
  CODE

  FIELD_MACROS = {"property", "property?", "getter", "getter?", "setter"}

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new
    source.ast.try &.accept(visitor)

    visitor.facts.select(&.utility_class?).map do |fact|
      Awesome::Issue.new(
        source.path,
        "UtilityClass",
        "#{fact.name}: all #{fact.class_methods} #{"method".pluralize(fact.class_methods)} " \
        "are class methods and nothing is instantiated — a namespace, not a type; " \
        "make it a module (call sites like #{fact.name}.method stay valid)",
        fact.location,
        source.excerpt_at(fact.line)
      )
    end
  end

  record Fact, name : String, class_methods : Int32, instance_behaviour : Bool,
    has_new_factory : Bool, location : Crystal::Location? do
    def utility_class? : Bool
      class_methods > 0 && !has_new_factory && !instance_behaviour
    end

    def line : Int32
      @location.try(&.line_number) || 0
    end
  end

  # Tracks class-level vs instance-level defs, macros and field macros
  # per ClassDef — nested types count for themselves, not their outer
  # class. Field macros count only at class-body level; inside a def a
  # `getter` call is just a call.
  private class Visitor < Crystal::Visitor
    getter facts = [] of Fact

    @contexts = [] of Context
    @body_depth = 0 # >0 inside a def/macro body

    def visit(node : Crystal::ClassDef)
      return true if node.struct? # value types carry data, not roles
      return true if node.superclass # inherited behaviour is unknowable
      @contexts << Context.new(node.name.to_s, node.location)
      true
    end

    def end_visit(node : Crystal::ClassDef)
      if ctx = @contexts.pop?
        facts << Fact.new(ctx.name, ctx.class_methods, ctx.instance_behaviour?,
          ctx.has_new_factory?, ctx.location)
      end
    end

    def visit(node : Crystal::Def)
      if ctx = @contexts.last?
        if node.receiver
          ctx.bump_class_method
          ctx.has_new_factory = true if node.name == "new"
        else
          ctx.mark_instance_behaviour
        end
      end
      @body_depth += 1
      true
    end

    def end_visit(node : Crystal::Def)
      @body_depth -= 1
    end

    def visit(node : Crystal::Macro)
      @contexts.last?.try(&.mark_instance_behaviour)
      @body_depth += 1
      true
    end

    def end_visit(node : Crystal::Macro)
      @body_depth -= 1
    end

    def visit(node : Crystal::Call)
      if @body_depth.zero? && @contexts.last? && FIELD_MACROS.includes?(node.name)
        @contexts.last.try(&.mark_instance_behaviour)
      end
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end

    # Name, location, class-method count, and whether any instance
    # behaviour exists (def, macro or field macro) — the counters
    # collapse into the boolean because only emptiness is a verdict.
    private class Context
      getter name : String
      getter location : Crystal::Location?
      getter class_methods = 0
      property? instance_behaviour = false
      property? has_new_factory = false

      def initialize(@name, @location)
      end

      def bump_class_method : Nil
        @class_methods += 1
      end

      def mark_instance_behaviour : Nil
        @instance_behaviour = true
      end
    end
  end

end

Awesome::Guard.registered << Awesome::Guards::UtilityClass
