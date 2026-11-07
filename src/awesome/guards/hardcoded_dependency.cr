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
  KIND              = "code"
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
        Awesome::I18n.t("guards.HardcodedDependency.main",
          owner: hit.owner.name, path: hit.path, where: hit.where,
          abstraction: abstraction.last_segment, impls_count: impls.size,
          impls: names),
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
end

Awesome::Guard.registered << Awesome::Guards::HardcodedDependency
