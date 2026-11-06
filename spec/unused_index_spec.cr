require "./spec_helper"

describe Awesome::Guards::UnusedIndex do
  it "flags an each_with_index block that ignores the index" do
    issues = guard_issues(Awesome::Guards::UnusedIndex, <<-CODE)
      items.each_with_index do |item, i|
        process item
      end
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("each")
    issues[0].message.should contain("i")
  end

  it "passes when the index is used" do
    guard_issues(Awesome::Guards::UnusedIndex, <<-CODE).should be_empty
      items.each_with_index do |item, i|
        log "\#{i}: \#{item}"
      end
    CODE
  end

  it "passes on plain each" do
    guard_issues(Awesome::Guards::UnusedIndex, <<-CODE).should be_empty
      items.each do |item|
        process item
      end
    CODE
  end

  it "treats underscore-prefixed index names as intentional" do
    guard_issues(Awesome::Guards::UnusedIndex, <<-CODE).should be_empty
      items.each_with_index do |item, _|
        process item
      end
      items.each_with_index do |item, _idx|
        process item
      end
    CODE
  end

  it "does not confuse the index with the element name" do
    guard_issues(Awesome::Guards::UnusedIndex, <<-CODE).should be_empty
      items.each_with_index do |i, _|
        process i
      end
    CODE
  end

  it "ignores blocks that do not take two parameters" do
    guard_issues(Awesome::Guards::UnusedIndex, <<-CODE).should be_empty
      items.each_with_index do |item|
        process item
      end
    CODE
  end
end
