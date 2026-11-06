require "./spec_helper"

describe Awesome::Guards::DeepInheritance do
  it "flags a three-level chain on the deepest class" do
    issues = guard_project_issues(Awesome::Guards::DeepInheritance, [<<-CODE])
      class A; end

      class B < A; end

      class C < B; end
      CODE
    issues.size.should eq(1)
    issues[0].message.should contain("C sits 3 levels deep in C < B < A")
    issues[0].line.should be > 0
  end

  it "does not flag chains at or above the external boundary" do
    issues = guard_project_issues(Awesome::Guards::DeepInheritance, [<<-CODE])
      class MyB < Kemal::Base; end # external parent caps the chain

      class MyA < MyB; end         # one visible hop
      CODE
    issues.should be_empty
  end

  it "counts hops across files but flags only once per chain" do
    issues = guard_project_issues(Awesome::Guards::DeepInheritance, [
      "class Base; end",
      "class Middle < Base; end",
      "class Leaf < Middle; end",
    ])
    issues.size.should eq(1)
    issues[0].message.should contain("Leaf sits 3 levels deep in Leaf < Middle < Base")
    issues[0].path.should eq("(test2)")
  end

  it "exempts exception and whitelisted stdlib hierarchies" do
    issues = guard_project_issues(Awesome::Guards::DeepInheritance, [<<-CODE])
      class AppError < Exception; end

      class DatabaseError < AppError; end

      class QueryError < DatabaseError; end
      CODE
    issues.should be_empty
  end

  it "honours a configured max_depth and allowed_superclasses" do
    code = ["class Base; end", "class Middle < Base; end"]
    guard_project_issues(Awesome::Guards::DeepInheritance, code).should be_empty
    yaml = "DeepInheritance:\n  max_depth: 1\n"
    issues = guard_project_issues(Awesome::Guards::DeepInheritance, code, yaml)
    issues.size.should eq(1)

    deep = [<<-CODE]
      class H < Kemal::Base; end

      class I < H; end

      class J < I; end
      CODE
    guard_project_issues(Awesome::Guards::DeepInheritance, deep).size.should eq(1)
    yaml2 = "DeepInheritance:\n  allowed_superclasses: [Kemal::Base]\n"
    guard_project_issues(Awesome::Guards::DeepInheritance, deep, yaml2).should be_empty
  end
end
