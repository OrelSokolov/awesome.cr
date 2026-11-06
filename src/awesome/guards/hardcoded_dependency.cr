# HardcodedDependency — a class bypassing an abstraction it itself uses.
#
# The only provable form of a welded-in dependency, all evidence
# syntactic: the project already declared a seam — one abstraction
# with two or more implementations (`Store` with `MemoryStore` and
# `RedisStore`, by subclassing or `include`) — and a class that works
# with that abstraction (a type annotation: `@store : Store`,
# `def rebuild(x : Store)`) news up a concrete implementation inside a
# method instead of accepting it. The class contradicts itself: the
# seam is declared in its own signature and welded shut one line below.
#
# Everything else is silent by design. Constructing a type without a
# seam (a parser building its result AST, a migration stamping Time),
# a class constructing a concrete type it never claimed to abstract
# over, external types, structs — syntax can't prove those wrong, and
# an earlier version of this guard that guessed ("any project class is
# a collaborator") drowned real issues in false positives. A seam the
# project actually wrote is the line where construction-in-a-method
# stops being a taste call and becomes today's bug.
class Awesome::Guards::HardcodedDependency < Awesome::Guard
  KIND = "smell"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for dependencies constructed, not injected — but only where
    the project itself proves the seam: `SomeConcrete.new` inside a
    method of a class that also declares the abstraction in a type
    annotation (`@store : Store`, `def f(x : Store)`), and the
    abstraction has two or more implementations in the project. The
    class contradicts its own signature; pass the dependency in
    instead. Without that evidence the guard stays silent —
    constructing result types, data and external types is not a smell
    a syntax check can prove.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    class Reporter
      def initialize(@store : Store,   # both Stores come from outside —
                     @cache : Store)   # the seam stays open
      end

      def rebuild
        warm(@cache)
      end
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    class Reporter
      def initialize(@store : Store)   # works with the abstraction…
      end

      def rebuild
        cache = MemoryStore.new        # …then welds one choice in
        cache.warm
      end
    end
  CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    [] of Awesome::Issue # evidence spans files — the project pass decides
  end

  def test_project(sources : Array(Awesome::Source), config : Awesome::GuardConfig) : Array(Awesome::Issue)
    issues = [] of Awesome::Issue
    index = Awesome::Index.new(sources)
    hardcoded = sources.flat_map { |source| Collector.new(source).run }
    allowed = config.strings("allowed", [] of String)
    annotations = {} of UInt64 => Array(String)

    hardcoded.each do |hit|
      next if allowed.any? { |pattern| allowed?(hit.path, pattern) }
      entry = index.resolve(hit.path)
      next unless entry && !entry.struct? && !entry.module?

      # The abstraction channels the constructed type implements: its
      # resolved superclass, and every resolved `include`d module.
      seams = seam_candidates(index, entry)
      next if seams.empty?

      # A def returning part of the seam family is a producer — a
      # chooser/factory (`def pick : Store; MemoryStore.new`) — not a
      # consumer bypassing the seam; its construction is the choice.
      if defn = hit.defn
        if return_type = defn.return_type
          if return_type.is_a?(Crystal::Path) || return_type.is_a?(Crystal::Generic)
            written = return_type.is_a?(Crystal::Generic) ? return_type.name.to_s.lchop("::") : return_type.to_s.lchop("::")
            if returned = index.resolve(written)
              next if returned == entry || seams.any? do |abstraction, impls|
                returned == abstraction || impls.any? { |impl| impl == returned }
              end
            end
          end
        end
      end

      # The owner must itself declare the abstraction — an annotation
      # naming the abstraction, the constructed type or a sibling.
      paths = (annotations[hit.owner.object_id] ||= Annotations.new(hit.owner).run)
      annotated = paths.compact_map { |path| index.resolve(path) }
      matched = seams.find do |abstraction, impls|
        impls.size >= 2 && annotated.any? do |ann|
          ann == abstraction || ann == entry || impls.any? { |impl| impl == ann }
        end
      end
      next unless matched

      abstraction, impls = matched
      names = impls.map(&.last_segment).uniq.join(", ")
      issues << Awesome::Issue.new(
        hit.source.path,
        "HardcodedDependency",
        "#{hit.owner.name} constructs #{hit.path}.new itself (#{hit.where}) — " \
        "but it works with #{abstraction.last_segment}, which has " \
        "#{impls.size} implementations (#{names}); pass the dependency " \
        "in instead, the welded-in line bypasses the seam",
        hit.location,
        hit.source.excerpt_at(hit.location.try(&.line_number) || 0)
      )
    end
    issues
  end

  # (abstraction, implementations) pairs the constructed type belongs
  # to: its superclass channel plus each `include`d module channel.
  # Unresolvable (external) abstractions are cut off — their other
  # implementations are unknowable from this codebase.
  private def seam_candidates(index : Awesome::Index, entry : Awesome::Index::TypeEntry)
    seams = [] of {Awesome::Index::TypeEntry, Array(Awesome::Index::TypeEntry)}
    if parent = entry.superclass
      index.resolve(parent).try { |resolved| seams << {resolved, index.implementations_of(resolved)} }
    end
    entry.included_modules.each do |name|
      next unless mod = index.resolve(name)
      next unless mod.module?
      seams << {mod, index.implementations_of(mod)}
    end
    seams
  end

  # Config whitelist entries match the written path exactly, as a
  # namespace prefix, or by last segment.
  private def allowed?(path : String, pattern : String) : Bool
    path == pattern ||
      path.starts_with?("#{pattern}::") ||
      pattern.split("::").last == path.split("::").last
  end

  # One `X.new` call site: receiver path as written, enclosing class
  # (the node — its annotations are evidence), enclosing def (or nil
  # for "class body"; its return type can reveal a producer), where
  # string, location, and the source it was seen in.
  record Hit, path : String, owner : Crystal::ClassDef, where : String,
    defn : Crystal::Def?, location : Crystal::Location?, source : Awesome::Source

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
      hardcoded << Hit.new(path, owner, where, defn, node.location, @source)
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

  # Type annotations of one class, as written paths: ivar/class-var
  # declarations (`@store : Store`) and parameter restrictions
  # (`def f(x : Store)`). Method *return* types are deliberately not
  # collected — `def pick : Store; MemoryStore.new; end` is a factory
  # choosing an implementation, not a consumer bypassing a seam.
  private class Annotations < Crystal::Visitor
    getter paths = [] of String

    def initialize(@owner : Crystal::ClassDef)
    end

    def run : Array(String)
      @owner.accept(self)
      paths
    end

    def visit(node : Crystal::TypeDeclaration)
      paths << written(node.declared_type) if restriction?(node.declared_type)
      true
    end

    def visit(node : Crystal::Arg)
      if restriction = node.restriction
        paths << written(restriction) if restriction?(restriction)
      end
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end

    private def restriction?(restriction : Crystal::ASTNode?) : Bool
      restriction.is_a?(Crystal::Path) || restriction.is_a?(Crystal::Generic)
    end

    private def written(restriction : Crystal::ASTNode) : String
      case restriction
      when Crystal::Generic then restriction.name.to_s.lchop("::")
      else                       restriction.to_s.lchop("::")
      end
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::HardcodedDependency
