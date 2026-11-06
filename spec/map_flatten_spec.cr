require "./spec_helper"

describe Awesome::Guards::MapFlatten do
  it "flags map with block followed by flatten" do
    issues = guard_issues(Awesome::Guards::MapFlatten, <<-CODE)
      words = lines.map { |l| l.split }.flatten
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain("flat_map")
  end

  it "flags the &.method shorthand form too" do
    issues = guard_issues(Awesome::Guards::MapFlatten, <<-CODE)
      words = lines.map(&.split).flatten
    CODE
    issues.size.should eq(1)
  end

  it "passes on flat_map" do
    guard_issues(Awesome::Guards::MapFlatten, <<-CODE).should be_empty
      words = lines.flat_map(&.split)
    CODE
  end

  it "ignores flatten without a preceding map" do
    guard_issues(Awesome::Guards::MapFlatten, <<-CODE).should be_empty
      nested = [[1, 2], [3]]
      flat = nested.flatten
    CODE
  end

  it "ignores a map whose result is used before flattening" do
    guard_issues(Awesome::Guards::MapFlatten, <<-CODE).should be_empty
      parts = lines.map(&.split)
      first = parts.first
      flat = parts.flatten
    CODE
  end
end
