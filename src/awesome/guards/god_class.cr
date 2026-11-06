# GodClass — one class doing too much.
#
# SRP can't be checked mechanically, but two honest proxy metrics can:
# a class with dozens of methods or instance variables is carrying many
# responsibilities whether or not it "should". The guard states facts
# ("32 methods, 14 ivars") — whether to split is the author's call.
#
# Structs and modules are skipped (data vs. namespace); abstract
# classes are not (contracts attract methods too). Thresholds are
# configurable, the defaults are deliberately high — the guard should
# point at outliers, not at ordinary classes.
class Awesome::Guards::GodClass < Awesome::Guard
  KIND = "smell"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for classes carrying too many responsibilities, measured by
    two proxy metrics: number of methods (default 25) and number of
    instance variables (default 10). The message states the facts
    ("32 methods, 14 ivars"), not a verdict. Structs and modules are
    skipped.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    class Cart
      getter items = [] of Item   # 3 methods, 2 ivars — one job

      def add(item : Item)
        items << item
      end

      def total : Int32
        items.sum(&.price)
      end
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    class Order            # 27 methods, 12 ivars — pricing, shipping,
      # ...                # emails and auditing all live here
    end
  CODE

  MAX_METHODS = 25
  MAX_IVARS   = 10

  FIELD_MACROS = {"property", "property?", "getter", "getter?", "setter"}

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)

    max_methods = config.int("max_methods", MAX_METHODS)
    max_ivars = config.int("max_ivars", MAX_IVARS)

    visitor.facts.select do |fact|
      fact.methods >= max_methods || fact.ivars >= max_ivars
    end.map do |fact|
      Awesome::Issue.new(
        source.path,
        "GodClass",
        "#{fact.name}: #{fact.methods} #{"method".pluralize(fact.methods)} and " \
        "#{fact.ivars} #{"ivar".pluralize(fact.ivars)} — too much for one class " \
        "(thresholds: #{max_methods} methods / #{max_ivars} ivars); " \
        "split the responsibilities",
        fact.location,
        source.excerpt_at(fact.location.try(&.line_number) || 0)
      )
    end
  end

  record Fact, name : String, methods : Int32, ivars : Int32, location : Crystal::Location?

  # Counts defs and unique ivar names per ClassDef — nested types count
  # for themselves, not for their outer class.
  private class Visitor < Crystal::Visitor
    getter facts = [] of Fact

    @contexts = [] of Context

    def initialize(@source : Awesome::Source)
    end

    def visit(node : Crystal::ClassDef)
      return true if node.struct? # value types carry data, not roles
      @contexts << Context.new(node.name.to_s, node.location)
      true
    end

    def end_visit(node : Crystal::ClassDef)
      if ctx = @contexts.pop?
        facts << Fact.new(ctx.name, ctx.methods, ctx.ivars.size, ctx.location)
      end
    end

    def visit(node : Crystal::Def)
      @contexts.last?.try(&.bump_method)
      true
    end

    def visit(node : Crystal::TypeDeclaration)
      if (var = node.var).is_a?(Crystal::InstanceVar)
        if ctx = @contexts.last?
          ctx.ivars << var.to_s
        end
      end
      true
    end

    def visit(node : Crystal::Assign | Crystal::OpAssign)
      if (target = node.target).is_a?(Crystal::InstanceVar)
        if ctx = @contexts.last?
          ctx.ivars << target.to_s
        end
      end
      true
    end

    def visit(node : Crystal::Call)
      return true unless @contexts.last? && FIELD_MACROS.includes?(node.name)
      node.args.each do |arg|
        name = case arg
               when Crystal::TypeDeclaration then arg.var.to_s
               else                               arg.to_s
               end
        name = name.lchop(':')
        ivar = name.starts_with?('@') ? name : "@#{name}"
        if ctx = @contexts.last?
          ctx.ivars << ivar
        end
      end
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end

    private class Context
      getter name : String
      getter location : Crystal::Location?
      getter methods = 0
      getter ivars = Set(String).new

      def initialize(@name, @location)
      end

      def bump_method : Nil
        @methods += 1
      end
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::GodClass
