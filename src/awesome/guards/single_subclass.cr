# SingleSubclass — inheritance "for the future" that never came.
#
# A base class with exactly one subclass is speculative hierarchy: the
# second implementation was planned but never written, and the base
# now adds a level of indirection with nothing to choose between.
# The subclass should hold its behaviour directly and *have* the base
# as a collaborator — or the two should merge back into one class.
#
# Project-wide (test_project): subclass counts need the whole project,
# so the guard works over the syntactic Index. Abstract bases are
# exempt (a contract written for extension is legitimate); bases
# defined outside the project are never examined — their subclasses
# are unknowable from this codebase alone.
class Awesome::Guards::SingleSubclass < Awesome::Guard
  KIND = "smell"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for speculative hierarchy: a non-abstract base class with
    exactly one subclass in the project. Inheritance "for the future"
    adds indirection with nothing to choose between — the subclass
    should compose or merge instead of being an only child. Abstract
    bases (contracts written for extension) and external bases are
    exempt.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    class Report                 # no base — behaviour held directly
      def initialize(@source : DataSource) # composition over hierarchy
      end
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    class ReportBase; end        # base exists only to be inherited

    class Report < ReportBase; end # the only subclass — merge them
  CODE

  def test_project(sources : Array(Awesome::Source), config : Awesome::GuardConfig) : Array(Awesome::Issue)
    issues = [] of Awesome::Issue
    index = Awesome::Index.new(sources)
    by_path = sources.map { |s| {s.path, s} }.to_h

    index.entries.each do |entry|
      next if entry.module?
      next unless parent_path = entry.superclass

      parent = index.resolve(parent_path)
      next unless parent && parent.qualified_name != entry.qualified_name
      next if parent.abstract? # a base written as a contract is legitimate

      siblings = index.subclasses_of(parent).reject(&.==(entry))
      next unless siblings.empty? # exactly one subclass: this entry

      issues << Awesome::Issue.new(
        entry.path,
        "SingleSubclass",
        "#{entry.qualified_name} is #{parent.qualified_name}'s only subclass — " \
        "an only child buys indirection, not polymorphism; compose " \
        "(have a #{parent.last_segment}) or merge the two",
        entry.location,
        by_path[entry.path]?.try(&.excerpt_at(entry.line))
      )
    end
    issues
  end
end

Awesome::Guard.registered << Awesome::Guards::SingleSubclass
