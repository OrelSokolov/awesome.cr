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
#
# Project-wide (test_project): "no instance behaviour" must hold over
# every fragment of the class — a reopening in another file can add an
# instance def, which per-file analysis would miss and flag a false
# positive. A subclass anywhere also exempts the class: `module` can't
# be inherited, so the "make it a module" advice would break it.
class Awesome::Guards::UtilityClass < Awesome::Guard
  KIND = "code"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for classes that are namespaces in disguise: every method
    is `def self.`, with no initialize, no instance defs and no field
    macros — never usefully instantiated. A module says the same and
    keeps every call site valid. Classes with a superclass, a subclass,
    or any instance behaviour (even added in another file by
    reopening) are skipped.
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
    [] of Awesome::Issue # evidence spans files — the project pass decides
  end

  def test_project(sources : Array(Awesome::Source), config : Awesome::GuardConfig) : Array(Awesome::Issue)
    index = Awesome::Index.new(sources)
    merged = {} of String => Fact

    sources.each do |source|
      source.ast.try &.accept(Visitor.new(source, merged))
    end

    merged.values.select(&.utility_class?).compact_map do |fact|
      # A subclass anywhere means the class is a parent — `module`
      # can't be inherited, the switch would break it.
      if entry = index.find(fact.qualified)
        next unless index.subclasses_of(entry).empty?
      end
      Awesome::Issue.new(
        fact.source.path,
        "UtilityClass",
        "#{fact.display}: all #{fact.class_methods} #{"method".pluralize(fact.class_methods)} " \
        "are class methods and nothing is instantiated — a namespace, not a type; " \
        "make it a module (call sites like #{fact.display}.method stay valid)",
        fact.location,
        fact.source.excerpt_at(fact.line)
      )
    end
  end

  # One class's evidence, merged across files when the class is
  # reopened: the qualified name identifies it, the first fragment's
  # location/source anchors the issue.
  record Fact, qualified : String, display : String, class_methods : Int32,
    instance_behaviour : Bool, has_new_factory : Bool, has_superclass : Bool,
    is_struct : Bool, location : Crystal::Location?, source : Awesome::Source do
    def utility_class? : Bool
      class_methods > 0 && !has_new_factory && !instance_behaviour &&
        !has_superclass && !is_struct
    end

    def line : Int32
      @location.try(&.line_number) || 0
    end
  end

  # Tracks class-level vs instance-level defs, macros and field macros
  # per ClassDef — nested types count for themselves, not their outer
  # class. Field macros count only at class-body level; inside a def a
  # `getter` call is just a call. Fragments merge into `merged` by
  # qualified name (a reopened class is one class, whatever file each
  # fragment lives in).
  private class Visitor < Crystal::Visitor
    @nesting = [] of String        # enclosing type names, innermost last
    @contexts = [] of Context      # ClassDef contexts, innermost last
    @body_depth = 0                # >0 inside a def/macro body

    def initialize(@source : Awesome::Source, @merged : Hash(String, Fact))
    end

    def visit(node : Crystal::ClassDef | Crystal::ModuleDef)
      @nesting << node.name.to_s
      if node.is_a?(Crystal::ClassDef)
        @contexts << Context.new(qualified_name, node)
      end
      true
    end

    def end_visit(node : Crystal::ClassDef | Crystal::ModuleDef)
      @nesting.pop
      if node.is_a?(Crystal::ClassDef) && (ctx = @contexts.pop?)
        merge(ctx)
      end
    end

    def visit(node : Crystal::Def)
      if ctx = @contexts.last?
        if node.receiver
          ctx.bump_class_method
          ctx.mark_new_factory if node.name == "new"
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

    private def qualified_name : String
      @nesting.join("::")
    end

    # Folds this fragment into the merged fact: counters add up, the
    # exemption flags OR together, the first fragment anchors the issue.
    private def merge(ctx : Context) : Nil
      qualified = ctx.qualified
      if fact = @merged[qualified]?
        @merged[qualified] = Fact.new(qualified, fact.display,
          fact.class_methods + ctx.class_methods,
          fact.instance_behaviour || ctx.instance_behaviour?,
          fact.has_new_factory || ctx.has_new_factory?,
          fact.has_superclass || ctx.has_superclass?,
          fact.is_struct || ctx.is_struct?,
          fact.location, fact.source)
      else
        @merged[qualified] = Fact.new(qualified, ctx.node.name.to_s.split("::").last,
          ctx.class_methods, ctx.instance_behaviour?, ctx.has_new_factory?,
          ctx.has_superclass?, ctx.is_struct?, ctx.node.location, @source)
      end
    end

    # One ClassDef fragment's counters and exemption flags — they
    # collapse into the flags because only emptiness is a verdict.
    # Plain ivars (no field macros): GodClass counts macro-declared
    # fields, and a lint tool's own plumbing shouldn't trip its guards.
    private class Context
      @class_methods = 0
      @instance_behaviour = false
      @has_new_factory = false

      def initialize(@qualified : String, @node : Crystal::ClassDef)
        @has_superclass = !@node.superclass.nil?
        @is_struct = @node.struct?
      end

      def qualified : String
        @qualified
      end

      def node : Crystal::ClassDef
        @node
      end

      def class_methods : Int32
        @class_methods
      end

      def instance_behaviour? : Bool
        @instance_behaviour
      end

      def has_new_factory? : Bool
        @has_new_factory
      end

      def has_superclass? : Bool
        @has_superclass
      end

      def is_struct? : Bool
        @is_struct
      end

      def bump_class_method : Nil
        @class_methods += 1
      end

      def mark_instance_behaviour : Nil
        @instance_behaviour = true
      end

      def mark_new_factory : Nil
        @has_new_factory = true
      end
    end
  end

end

Awesome::Guard.registered << Awesome::Guards::UtilityClass
