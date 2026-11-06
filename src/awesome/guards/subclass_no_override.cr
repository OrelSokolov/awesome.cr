# SubclassNoOverride — inheritance for reuse, not polymorphism.
#
# When a subclass overrides none of the parent's methods, it doesn't
# specialize behaviour — it just takes it. Nothing about the subclass
# differs through the parent's interface, which means the hierarchy
# exists to avoid copying code, not to model two variants of one
# concept. The fix is composition: the taker should *have* the helper
# as a collaborator instead of *being* it.
#
# Project-wide (test_project): the parent's method list usually lives
# in another file, so the guard pairs subclasses with parents from the
# syntactic Index and compares def names. Only the direct parent is
# compared; external parents are skipped (their method list is
# unknowable); abstract parent methods don't count — those exist to
# be overridden and are covered by the compiler, not by reuse.
class Awesome::Guards::SubclassNoOverride < Awesome::Guard
  KIND = "code"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for inheritance of code instead of behaviour: a subclass
    that overrides none of its parent's methods just takes the
    implementation — it should have the helper as a collaborator
    instead of being it. Only the direct, project-defined parent is
    compared; abstract parent methods don't count.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    class AuditedSave           # specialization: behaviour differs
      def initialize(@repo : Repo)
      end

      def save(item)            # overrides Repo#save — its own take
        log(item)
        @repo.save(item)
      end
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    class Repo
      def save(item); end
    end

    class CachedRepo < Repo     # overrides nothing — only takes
      def cache_key(item); end
    end
  CODE

  def test_project(sources : Array(Awesome::Source), config : Awesome::GuardConfig) : Array(Awesome::Issue)
    issues = [] of Awesome::Issue
    index = Awesome::Index.new(sources)
    by_path = sources.map { |s| {s.path, s} }.to_h

    index.entries.each do |entry|
      next if entry.module?
      next unless parent_path = entry.superclass
      next if entry.def_names.empty? # empty marker class — separate case, not ours

      parent = index.resolve(parent_path)
      next unless parent # external parent: method list unknowable
      next if parent.qualified_name == entry.qualified_name
      next if parent.def_names.empty? # nothing to override — nothing being taken

      overridable = parent.def_names # both regular and abstract defs;
      next unless (entry.def_names & overridable).empty?

      issues << Awesome::Issue.new(
        entry.path,
        "SubclassNoOverride",
        "#{entry.qualified_name} overrides none of #{parent.qualified_name}'s " \
        "methods — inheritance for code reuse, not polymorphism; have a " \
        "#{parent.last_segment} instead of being one",
        entry.location,
        by_path[entry.path]?.try(&.excerpt_at(entry.line))
      )
    end
    issues
  end
end

Awesome::Guard.registered << Awesome::Guards::SubclassNoOverride
