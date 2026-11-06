# DeepInheritance — inheritance used instead of composition.
#
# Deep class chains are fragile: every level adds contracts the levels
# below must honour, and behaviour becomes spread across files instead
# of delegated to collaborators. A chain three levels deep almost
# always means "wanted to reuse code" — which composition (`has a`,
# not `is a`) expresses without the coupling.
#
# Project-wide (test_project): hierarchies usually span files, so the
# guard walks the syntactic Index. Only hops between classes defined
# in the project count — an external parent (a shard, the stdlib)
# caps the chain, because what lies beyond is unknowable from syntax.
# Exception hierarchies and whitelisted stdlib bases are exempt: deep
# error taxonomies are normal.
class Awesome::Guards::DeepInheritance < Awesome::Guard
  KIND = "code"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for inheritance chains three or more levels deep
    (configurable). Every level adds contracts the levels below must
    honour; composition (having, not being) expresses reuse without
    the coupling. Only hops between classes defined in the project
    count — external parents (shards, stdlib) cap the chain. Exception
    hierarchies are exempt.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    class Parser                    # 1 level: each class delegates
      def initialize(@lexer : Lexer) # to collaborators it holds
      end
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    class A; end
    class B < A; end
    class C < B; end # 2 hops deep — have A/B instead of being them
  CODE

  # Visible hops between project classes before a chain is flagged.
  MAX_DEPTH = 2

  # Bases whose inheritance is legitimate almost always — deep stdlib
  # taxonomies (exceptions above all) are normal, not a smell.
  DEFAULT_ALLOWED_SUPERCLASSES = ["Exception", "Reference", "Object",
                                  "Struct", "Enum", "Value", "IO",
                                  "Comparable", "Enumerable"]

  def test_project(sources : Array(Awesome::Source), config : Awesome::GuardConfig) : Array(Awesome::Issue)
    issues = [] of Awesome::Issue
    index = Awesome::Index.new(sources)
    by_path = sources.map { |s| {s.path, s} }.to_h
    max_depth = config.int("max_depth", MAX_DEPTH)
    allowed = config.strings("allowed_superclasses", DEFAULT_ALLOWED_SUPERCLASSES)

    index.entries.each do |entry|
      next if entry.module? || entry.superclass.nil?
      chain, hops, whitelisted = visible_chain(index, entry, allowed)
      next if whitelisted
      next unless hops >= max_depth

      issues << Awesome::Issue.new(
        entry.path,
        "DeepInheritance",
        "#{entry.qualified_name} sits #{chain.size} #{"level".pluralize(chain.size)} deep " \
        "in #{chain.join(" < ")} — prefer composition (have a " \
        "collaborator instead of being one)",
        entry.location,
        by_path[entry.path]?.try(&.excerpt_at(entry.line))
      )
    end
    issues
  end

  # The chain from `entry` up, as display names (child first, external
  # tail reduced to its last segment), the visible hop count, and
  # whether the chain reaches a whitelisted base anywhere.
  private def visible_chain(index : Awesome::Index, entry : Awesome::Index::TypeEntry,
                            allowed : Array(String))
    chain = [entry.qualified_name]
    hops = 0
    whitelisted = false
    current = entry
    visited = Set{entry.qualified_name}

    while parent_path = current.superclass
      if parent = index.resolve(parent_path)
        whitelisted ||= allowed_base?(parent_path, allowed) ||
                        allowed_base?(parent.qualified_name, allowed)
        break unless visited.add?(parent.qualified_name) # reopen/cycle guard

        chain << parent.qualified_name
        hops += 1
        current = parent
      else
        chain << parent_path.split("::").last # external tail, for context
        whitelisted ||= allowed_base?(parent_path, allowed)
        break
      end
    end
    {chain, hops, whitelisted}
  end

  private def allowed_base?(path : String, allowed : Array(String)) : Bool
    segment = path.split("::").last
    allowed.any? do |entry|
      entry == path || entry.split("::").last == segment
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::DeepInheritance
