# GodClass — one class doing too much.
#
# SRP can't be checked mechanically, but two honest proxy metrics can:
# a class with dozens of methods or instance variables is carrying many
# responsibilities whether or not it "should". The guard states facts
# ("32 methods, 14 ivars") — whether to split is the author's call.
#
# Project-wide (test_project): a class reopened in another file is one
# class — counters merge across its fragments, so splitting a god
# class over two files no longer hides it. Structs and modules are
# skipped (data vs. namespace); abstract classes are not (contracts
# attract methods too). Thresholds are configurable, the defaults are
# deliberately high — the guard should point at outliers, not at
# ordinary classes.
class Awesome::Guards::GodClass < Awesome::Guard
  KIND = "code"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for classes carrying too many responsibilities, measured by
    two proxy metrics: number of methods (default 25) and number of
    instance variables (default 10). The message states the facts
    ("32 methods, 14 ivars"), not a verdict. Counts span the whole
    project — a class reopened in another file is one class. Structs
    and modules are skipped.
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
    [] of Awesome::Issue # evidence spans files — the project pass decides
  end

  def test_project(sources : Array(Awesome::Source), config : Awesome::GuardConfig) : Array(Awesome::Issue)
    merged = {} of String => Fact
    sources.each do |source|
      source.ast.try &.accept(Visitor.new(source, merged))
    end

    max_methods = config.int("max_methods", MAX_METHODS)
    max_ivars = config.int("max_ivars", MAX_IVARS)

    merged.values.select do |fact|
      !fact.is_struct && (fact.methods >= max_methods || fact.ivars.size >= max_ivars)
    end.map do |fact|
      Awesome::Issue.new(
        fact.source.path,
        "GodClass",
        Awesome::I18n.t("guards.GodClass.main",
          display: fact.display,
          methods: Awesome::I18n.t("guards.GodClass.methods", count: fact.methods),
          ivars: Awesome::I18n.t("guards.GodClass.ivars", count: fact.ivars.size),
          methods_threshold: max_methods, ivars_threshold: max_ivars),
        fact.location,
        fact.source.excerpt_at(fact.line)
      )
    end
  end

  # One class's evidence, merged across files when the class is
  # reopened: the qualified name identifies it, the first fragment's
  # location/source anchors the issue.
  record Fact, qualified : String, display : String, methods : Int32, ivars : Set(String),
    is_struct : Bool, location : Crystal::Location?, source : Awesome::Source do
    def line : Int32
      @location.try(&.line_number) || 0
    end
  end

  # Counts defs and unique ivar names per ClassDef — nested types count
  # for themselves, not for their outer class. Fragments merge into
  # `merged` by qualified name (a reopened class is one class, whatever
  # file each fragment lives in).
  private class Visitor < Crystal::Visitor
    @nesting = [] of String   # enclosing type names, innermost last
    @contexts = [] of Context # ClassDef contexts, innermost last

    def initialize(@source : Awesome::Source, @merged : Hash(String, Fact))
    end

    def visit(node : Crystal::ClassDef | Crystal::ModuleDef)
      @nesting << node.name.to_s
      if node.is_a?(Crystal::ClassDef)
        @contexts << Context.new(@nesting.join("::"), node)
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
      @contexts.last?.try(&.bump_method)
      true
    end

    def visit(node : Crystal::TypeDeclaration)
      if (var = node.var).is_a?(Crystal::InstanceVar)
        @contexts.last?.try { |ctx| ctx.ivars << var.to_s }
      end
      true
    end

    def visit(node : Crystal::Assign | Crystal::OpAssign)
      if (target = node.target).is_a?(Crystal::InstanceVar)
        @contexts.last?.try { |ctx| ctx.ivars << target.to_s }
      end
      true
    end

    def visit(node : Crystal::Call)
      return true unless (ctx = @contexts.last?) && FIELD_MACROS.includes?(node.name)
      node.args.each do |arg|
        name = case arg
               when Crystal::TypeDeclaration then arg.var.to_s
               else                               arg.to_s
               end
        name = name.lchop(':')
        ivar = name.starts_with?('@') ? name : "@#{name}"
        ctx.ivars << ivar
      end
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end

    # Folds this fragment into the merged fact: counters add up, ivar
    # names union, the first fragment anchors the issue.
    private def merge(ctx : Context) : Nil
      qualified = ctx.qualified
      if fact = @merged[qualified]?
        @merged[qualified] = Fact.new(qualified, fact.display,
          fact.methods + ctx.methods, fact.ivars | ctx.ivars,
          fact.is_struct || ctx.node.struct?, fact.location, fact.source)
      else
        @merged[qualified] = Fact.new(qualified, ctx.node.name.to_s.split("::").last,
          ctx.methods, ctx.ivars, ctx.node.struct?, ctx.node.location, @source)
      end
    end

    # One ClassDef fragment's counters — mutable, so a reopened class's
    # fragments fold into one Fact without copying sets around.
    private class Context
      getter qualified : String
      getter node : Crystal::ClassDef
      getter methods = 0
      getter ivars = Set(String).new

      def initialize(@qualified, @node)
      end

      def bump_method : Nil
        @methods += 1
      end
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::GodClass
