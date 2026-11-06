require "./spec_helper"

describe Awesome::Guards::MapCompact do
  it "flags map { … }.compact" do
    issues = guard_issues(Awesome::Guards::MapCompact, <<-CODE)
      names = users.map { |u| u.email }.compact
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain("compact_map")
  end

  it "flags the &.method shorthand form" do
    issues = guard_issues(Awesome::Guards::MapCompact, <<-CODE)
      names = users.map(&.email).compact
    CODE
    issues.size.should eq(1)
  end

  it "does not flag compact_map itself" do
    guard_issues(Awesome::Guards::MapCompact, <<-CODE).should be_empty
      names = users.compact_map(&.email)
    CODE
  end

  it "does not flag a plain compact" do
    guard_issues(Awesome::Guards::MapCompact, <<-CODE).should be_empty
      names = users.compact
    CODE
  end

  it "does not flag compact on other transforms" do
    guard_issues(Awesome::Guards::MapCompact, <<-CODE).should be_empty
      names = users.select { |u| u.email }.compact
    CODE
  end
end
