require "./spec_helper"

describe Awesome::Guards::SelectFirst do
  it "flags select { … }.first" do
    issues = guard_issues(Awesome::Guards::SelectFirst, <<-CODE)
      first_bad = results.select { |r| r.error? }.first
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain("find")
  end

  it "flags select { … }.first? and suggests find?" do
    issues = guard_issues(Awesome::Guards::SelectFirst, <<-CODE)
      first_bad = results.select { |r| r.error? }.first?
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("find?")
  end

  it "flags the &.method shorthand form" do
    issues = guard_issues(Awesome::Guards::SelectFirst, <<-CODE)
      first_bad = results.select(&.error?).first
    CODE
    issues.size.should eq(1)
  end

  it "does not flag a plain first" do
    guard_issues(Awesome::Guards::SelectFirst, <<-CODE).should be_empty
      head = results.first
    CODE
  end

  it "does not flag first(n) — that returns an Array" do
    guard_issues(Awesome::Guards::SelectFirst, <<-CODE).should be_empty
      top3 = results.select { |r| r.error? }.first(3)
    CODE
  end

  it "does not flag first on other transforms" do
    guard_issues(Awesome::Guards::SelectFirst, <<-CODE).should be_empty
      head = results.sort.first
      head = results.map { |r| r.next }.first
    CODE
  end
end
