require "./spec_helper"

describe Awesome::Guards::TimesIndex do
  it "flags xs.size.times indexing xs" do
    issues = guard_issues(Awesome::Guards::TimesIndex, <<-CODE)
      items.size.times do |i|
        process items[i]
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain("each")
  end

  it "flags indexing nested deeper in the block" do
    issues = guard_issues(Awesome::Guards::TimesIndex, <<-CODE)
      items.size.times do |i|
        if visible
          process items[i]
        end
      end
    CODE
    issues.size.should eq(1)
  end

  it "does not flag when the index is unused" do
    guard_issues(Awesome::Guards::TimesIndex, <<-CODE).should be_empty
      items.size.times do |i|
        process i
      end
    CODE
  end

  it "does not flag indexing a different collection" do
    guard_issues(Awesome::Guards::TimesIndex, <<-CODE).should be_empty
      items.size.times do |i|
        process others[i]
      end
    CODE
  end

  it "does not flag plain n.times" do
    guard_issues(Awesome::Guards::TimesIndex, <<-CODE).should be_empty
      10.times do |i|
        process items[i]
      end
    CODE
  end

  it "does not flag blocks with more than one argument" do
    guard_issues(Awesome::Guards::TimesIndex, <<-CODE).should be_empty
      items.size.times do |i, j|
        process items[i]
      end
    CODE
  end
end
