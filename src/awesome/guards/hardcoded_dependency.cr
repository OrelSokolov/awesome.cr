# HardcodedDependency — a class constructing its own dependencies.
#
# DIP, the one SOLID letter that is mechanically detectable: a class
# that calls `SomeConcrete.new` itself (outside `initialize`) can
# neither be substituted in tests nor reconfigured — the dependency is
# welded in. Constructor injection (`def initialize(@engine : Engine)`)
# keeps the class in charge of using, not creating.
#
# Project-wide (test_project): whether a constructed type is a
# collaborator or mere data is decided by evidence from the syntactic
# Index, not by guesswork. A type defined in the project is known: a
# `struct` is a value object (constructing it is data plumbing), a
# `class` is a real collaborator weld. A type not defined in the
# project (a shard, the stdlib) is unknowable from syntax, so it is
# silent by default — `flag_externals: true` opts back into flagging
# external constructions, with the `allowed` whitelist for exceptions.
# Better a false negative than a false positive.
class Awesome::Guards::HardcodedDependency < Awesome::Guard
  KIND = "smell"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for dependencies constructed, not injected: a hardcoded
    `SomeConcrete.new` inside a class (outside `initialize`) is welded
    in — it cannot be substituted in tests or reconfigured. Pass the
    dependency in through the constructor instead. Only classes
    defined in the project count — a project struct is data plumbing,
    external types (shards, stdlib) are silent unless
    `flag_externals: true`. Polymorphic `klass.new` calls, factory
    class-methods (`def self.build`), exceptions, a class constructing
    itself or its own nested types are never flagged.
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
  # dependency. Applies to external constructions when
  # `flag_externals` is on; entries match the written path exactly, as
  # a namespace prefix ("Crystal" also covers "Crystal::Parser"), or
  # by last segment ("Awesome::Source" covers a relative "Source.new").
  DEFAULT_ALLOWED = ["Array", "Hash", "Set", "Deque", "Slice",
                     "String", "IO", "Time", "Random", "Crystal"]

  # Fire once the class hardcodes at least this many dependencies.
  MIN_DEPENDENCIES = 1

  # Whether types not defined in the project (shards, stdlib) are
  # flagged too. Off by default: from syntax alone an external type
  # can't be told apart from a value object (`Egui::Pos2.new` is data,
  # `HTTP::Client.new` is a service), and a guess that noisy is worse
  # than silence.
  FLAG_EXTERNALS = false

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    [] of Awesome::Issue # evidence spans files — the project pass decides
  end

  def test_project(sources : Array(Awesome::Source), config : Awesome::GuardConfig) : Array(Awesome::Issue)
    issues = [] of Awesome::Issue
    index = Awesome::Index.new(sources)
    hardcoded = sources.flat_map { |source| Collector.new(source).run }

    flag_externals = config.bool("flag_externals", FLAG_EXTERNALS)
    allowed = DEFAULT_ALLOWED + config.strings("allowed", [] of String)
    min = config.int("min_dependencies", MIN_DEPENDENCIES)

    hardcoded.reject! do |hit|
      if entry = index.resolve(hit.path)
        # Project type — decided by evidence: a struct (or module) is
        # data plumbing, a class is a collaborator.
        entry.struct? || entry.module?
      else
        # External (a shard, the stdlib) — silent unless opted in.
        !flag_externals
      end
    end
    # The whitelist carves exceptions out of whatever is left — project
    # classes (plumbing like Awesome::Issue) and, in flag_externals
    # mode, external types (stdlib data by default).
    hardcoded.reject! do |hit|
      allowed.any? do |pattern|
        hit.path == pattern ||
          hit.path.starts_with?("#{pattern}::") ||
          pattern.split("::").last == hit.path.split("::").last
      end
    end
    counts = {} of String => Int32
    hardcoded.each { |hit| counts[hit.owner] = (counts[hit.owner]? || 0) + 1 }
    counts.reject! { |_, count| count < min }

    hardcoded.each do |hit|
      next unless counts[hit.owner]?
      issues << Awesome::Issue.new(
        hit.source.path,
        "HardcodedDependency",
        "#{hit.owner} constructs #{hit.path}.new itself (#{hit.where}) — " \
        "pass the dependency in instead; a welded-in type can't be " \
        "substituted in tests",
        hit.location,
        hit.source.excerpt_at(hit.location.try(&.line_number) || 0)
      )
    end
    issues
  end

  # One `X.new` call site: receiver path as written, enclosing class,
  # enclosing def (or "class body"), location, and the source it was
  # seen in (the project pass spans files, an issue is anchored to one).
  record Hit, path : String, owner : String, where : String,
    location : Crystal::Location?, source : Awesome::Source

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
      hardcoded << Hit.new(path, owner.name.to_s, where, node.location, @source)
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
