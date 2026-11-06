require "./spec_helper"

describe Awesome::Guards::SingleSubclass do
  it "flags the only subclass of a non-abstract base" do
    issues = guard_project_issues(Awesome::Guards::SingleSubclass, [<<-CODE])
      class StoreBase
        def key_for(name); end
      end

      class RedisStore < StoreBase
        def key_for(name); end
      end
      CODE
    issues.size.should eq(1)
    issues[0].message.should contain("RedisStore is StoreBase's only subclass")
    issues[0].line.should be > 0
  end

  it "does not flag bases with two or more subclasses" do
    issues = guard_project_issues(Awesome::Guards::SingleSubclass, [<<-CODE])
      class StoreBase; end

      class RedisStore < StoreBase; end

      class MemoryStore < StoreBase; end
      CODE
    issues.should be_empty
  end

  it "exempts abstract bases — contracts written for extension" do
    issues = guard_project_issues(Awesome::Guards::SingleSubclass, [<<-CODE])
      abstract class StoreBase
        abstract def key_for(name)
      end

      class RedisStore < StoreBase
        def key_for(name); end
      end
      CODE
    issues.should be_empty
  end

  it "exempts external bases and counts subclasses across files" do
    issues = guard_project_issues(Awesome::Guards::SingleSubclass, [
      "class Handler < Kemal::Base; end", # external base — not examined
      "class StoreBase; end",
    ])
    issues.should be_empty

    two = guard_project_issues(Awesome::Guards::SingleSubclass, [
      "class StoreBase; end",
      "class RedisStore < StoreBase; end",
      "class MemoryStore < StoreBase; end",
    ])
    two.should be_empty

    one = guard_project_issues(Awesome::Guards::SingleSubclass, [
      "class StoreBase; end",
      "class RedisStore < StoreBase; end",
    ])
    one.size.should eq(1)
    one[0].path.should eq("(test1)")
  end

  it "resolves hierarchies nested in modules" do
    issues = guard_project_issues(Awesome::Guards::SingleSubclass, [<<-CODE])
      module Stores
        class Base; end

        class Redis < Base; end
      end
      CODE
    issues.size.should eq(1)
    issues[0].message.should contain("Stores::Redis is Stores::Base's only subclass")
  end
end
