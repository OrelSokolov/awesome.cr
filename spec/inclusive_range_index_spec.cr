require "./spec_helper"

describe Awesome::Guards::InclusiveRangeIndex do
  it "flags an inclusive range over size indexing the receiver" do
    issues = guard_issues(Awesome::Guards::InclusiveRangeIndex, <<-CODE)
      (0..items.size).each do |i|
        process items[i]
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain("0...items.size")
  end

  it "flags upto over size" do
    issues = guard_issues(Awesome::Guards::InclusiveRangeIndex, <<-CODE)
      1.upto(rows.size) do |j|
        render rows[j]
      end
    CODE
    issues.size.should eq(1)
  end

  it "flags indexing nested deeper in the block" do
    issues = guard_issues(Awesome::Guards::InclusiveRangeIndex, <<-CODE)
      (0..items.size).each do |i|
        process items[i] if visible
      end
    CODE
    issues.size.should eq(1)
  end

  it "does not flag the exclusive range" do
    guard_issues(Awesome::Guards::InclusiveRangeIndex, <<-CODE).should be_empty
      (0...items.size).each do |i|
        process items[i]
      end
    CODE
  end

  it "does not flag times" do
    guard_issues(Awesome::Guards::InclusiveRangeIndex, <<-CODE).should be_empty
      items.size.times do |i|
        process items[i]
      end
    CODE
  end

  it "does not flag an adjusted range end" do
    guard_issues(Awesome::Guards::InclusiveRangeIndex, <<-CODE).should be_empty
      (0..items.size - 1).each do |i|
        process items[i]
      end
    CODE
  end

  it "does not flag an offset index" do
    guard_issues(Awesome::Guards::InclusiveRangeIndex, <<-CODE).should be_empty
      (1..items.size).each do |i|
        process items[i - 1]
      end
    CODE
  end

  it "does not flag indexing a different collection" do
    guard_issues(Awesome::Guards::InclusiveRangeIndex, <<-CODE).should be_empty
      (0..items.size).each do |i|
        process others[i]
      end
    CODE
  end
end
