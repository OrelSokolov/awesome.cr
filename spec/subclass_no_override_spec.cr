require "./spec_helper"

describe Awesome::Guards::SubclassNoOverride do
  it "flags a subclass that overrides nothing" do
    issues = guard_project_issues(Awesome::Guards::SubclassNoOverride, [<<-CODE])
      class Repo
        def save(item); end

        def delete(item); end
      end

      class CachedRepo < Repo
        def cache_key(item); end
      end
      CODE
    issues.size.should eq(1)
    issues[0].message.should contain("CachedRepo overrides none of Repo's methods")
    issues[0].line.should be > 0
  end

  it "does not flag a subclass overriding at least one parent method" do
    issues = guard_project_issues(Awesome::Guards::SubclassNoOverride, [<<-CODE])
      class Repo
        def save(item); end
      end

      class AuditedRepo < Repo
        def save(item); end # specialization, not just taking
      end
      CODE
    issues.should be_empty
  end

  it "skips external parents, empty subclasses and modules" do
    issues = guard_project_issues(Awesome::Guards::SubclassNoOverride, [
      "class Handler < Kemal::Base; end",     # external parent
      "class Repo; def save; end; end\n\nclass Tag < Repo; end", # empty marker class
    ])
    issues.should be_empty
  end

  it "compares with the direct parent only, across files" do
    issues = guard_project_issues(Awesome::Guards::SubclassNoOverride, [
      "class A; def a; end; end",
      "class B < A; def a; end; end", # overrides A#a — not flagged
      "class C < B; def c; end; end", # C vs B (direct): no overlap → flagged
    ])
    issues.size.should eq(1)
    issues[0].message.should contain("C overrides none of B's methods")
    issues[0].path.should eq("(test2)")
  end
end
