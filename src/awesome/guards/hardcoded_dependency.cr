# HardcodedDependency — a class constructing its own dependencies.
#
# DIP, the one SOLID letter that is mechanically detectable: a class
# that calls `SomeConcrete.new` itself (outside `initialize`) can
# neither be substituted in tests nor reconfigured — the dependency is
# welded in. Constructor injection (`def initialize(@engine : Engine)`)
# keeps the class in charge of using, not creating.
#
# Purely syntactic (per-file, no semantic pass), so the skips are
# conservative: polymorphic `klass.new`, factory class-methods
# (`def self.build`), exceptions, whitelisted stdlib data types and
# types nested inside the same class (private helpers like `Visitor`)
# are never flagged. Better a false negative than a false positive.
class Awesome::Guards::HardcodedDependency < Awesome::Guard
  KIND = "smell"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for dependencies constructed, not injected: a hardcoded
    `SomeConcrete.new` inside a class (outside `initialize`) is welded
    in — it cannot be substituted in tests or reconfigured. Pass the
    dependency in through the constructor instead. Polymorphic
    `klass.new` calls, factory class-methods (`def self.build`),
    exceptions, a class constructing itself or its own nested types,
    and a whitelist of stdlib data types are never flagged.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    class Car
      def initialize(@engine : Engine) # injected — replaceable
      end

      def start
        @engine.run
      end
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    class Car
      def start
        engine = Engine.new # hardcoded — welded-in dependency
        engine.run
      end
    end
  CODE

  # Types whose construction is data plumbing, not a collaborator
  # dependency. The config list extends this one; entries match the
  # written path exactly, as a namespace prefix ("Crystal" also covers
  # "Crystal::Parser"), or by last segment ("Awesome::Source" covers a
  # relative "Source.new").
  DEFAULT_ALLOWED = ["Array", "Hash", "Set", "Deque", "Slice",
                     "String", "IO", "Time", "Random", "Crystal"]

  # Fire once the class hardcodes at least this many dependencies.
  MIN_DEPENDENCIES = 1

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    issues = [] of Awesome::Issue
    hardcoded = Collector.new(source).run

    allowed = DEFAULT_ALLOWED + config.strings("allowed", [] of String)
    min = config.int("min_dependencies", MIN_DEPENDENCIES)

    hardcoded.reject! do |hit|
      allowed.any? do |entry|
        hit.path == entry ||
          hit.path.starts_with?("#{entry}::") ||
          entry.split("::").last == hit.path.split("::").last
      end
    end
    counts = {} of String => Int32
    hardcoded.each { |hit| counts[hit.owner] = (counts[hit.owner]? || 0) + 1 }
    counts.reject! { |_, count| count < min }

    hardcoded.each do |hit|
      next unless counts[hit.owner]?
      issues << Awesome::Issue.new(
        source.path,
        "HardcodedDependency",
        "#{hit.owner} constructs #{hit.path}.new itself (#{hit.where}) — " \
        "pass the dependency in instead; a welded-in type can't be " \
        "substituted in tests",
        hit.location,
        source.excerpt_at(hit.location.try(&.line_number) || 0)
      )
    end
    issues
  end

  # One `X.new` call site: receiver path as written, enclosing class,
  # enclosing def (or "class body"), location.
  record Hit, path : String, owner : String, where : String, location : Crystal::Location?

  # First pass: map ClassDef → names of types nested inside it (any
  # depth) — constructing your own nested helpers is not a dependency.
  # Second pass: collect `Path.new` calls not covered by the skips.
  private class Collector < Crystal::Visitor
    getter hardcoded = [] of Hit

    @nested_names = {} of UInt64 => Set(String)
    @classes = [] of Crystal::ClassDef
    @defs = [] of Crystal::Def?

    def initialize(@source : Awesome::Source)
    end

    def run : Array(Hit)
      @source.ast.try &.accept(Nester.new(@nested_names))
      @source.ast.try &.accept(self)
      hardcoded
    end

    def visit(node : Crystal::ClassDef)
      @classes << node
      true
    end

    def end_visit(node : Crystal::ClassDef)
      @classes.pop
    end

    def visit(node : Crystal::Def)
      @defs << node
      true
    end

    def end_visit(node : Crystal::Def)
      @defs.pop
    end

    def visit(node : Crystal::Call)
      collect(node) if node.name == "new" && node.obj.is_a?(Crystal::Path)
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end

    private def collect(node : Crystal::Call) : Nil
      return unless owner = @classes.last?    # only inside a class body
      return if owner.struct?                  # value types carry data, not collaborators
      path = node.obj.as(Crystal::Path).to_s.lchop("::")
      segment = path.split("::").last
      return if segment.ends_with?("Error") || segment.ends_with?("Exception")
      return if @classes.any? { |c| c.name.to_s.split("::").last == segment } # the class building itself / its own nested helpers
      return if @classes.any? { |c| (@nested_names[c.object_id]? || Set(String).new).includes?(segment) }

      defn = @defs.last?
      return if defn && defn.name == "initialize" # assigning fields in initialize
      return if defn && defn.receiver              # factory class-methods (def self.build)

      where = defn ? "#{owner.name}##{defn.name}" : "#{owner.name} class body"
      hardcoded << Hit.new(path, owner.name.to_s, where, node.location)
    end
  end

  # Collects the names of types defined inside each ClassDef, for
  # every enclosing level (a type nested two levels deep is visible to
  # both ancestors). Type-defining nodes only — ClassDef/ModuleDef,
  # `record` macro calls, aliases and enums.
  private class Nester < Crystal::Visitor
    @stack = [] of Crystal::ClassDef

    def initialize(@nested_names : Hash(UInt64, Set(String)))
    end

    def visit(node : Crystal::ClassDef | Crystal::ModuleDef)
      register(node.name.to_s)
      if node.is_a?(Crystal::ClassDef)
        @stack << node
      end
      true
    end

    def end_visit(node : Crystal::ClassDef)
      @stack.pop
    end

    def visit(node : Crystal::Call)
      register(node.args.first.to_s) if node.name == "record" && node.args.first?
      true
    end

    def visit(node : Crystal::Alias | Crystal::EnumDef)
      register(node.name.to_s)
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end

    private def register(name : String) : Nil
      segment = name.split("::").last
      @stack.each do |outer|
        (@nested_names[outer.object_id] ||= Set(String).new) << segment
      end
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::HardcodedDependency
