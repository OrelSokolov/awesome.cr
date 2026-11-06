require "./spec_helper"

describe Awesome::Guards::IndexLookahead do
  it "flags i + 1 inside size.times on the same receiver" do
    issues = guard_issues(Awesome::Guards::IndexLookahead, <<-CODE)
      items.size.times do |i|
        process items[i + 1]
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(2)
    issues[0].message.should contain("past the end")
  end

  it "flags i + 1 inside an exclusive range over size" do
    issues = guard_issues(Awesome::Guards::IndexLookahead, <<-CODE)
      (0...rows.size).each do |j|
        compare rows[j], rows[j + 1]
      end
    CODE
    issues.size.should eq(1)
  end

  it "does not flag a bare index (TimesIndex territory)" do
    guard_issues(Awesome::Guards::IndexLookahead, <<-CODE).should be_empty
      items.size.times do |i|
        process items[i]
      end
    CODE
  end

  it "does not flag when the body compares the index" do
    guard_issues(Awesome::Guards::IndexLookahead, <<-CODE).should be_empty
      items.size.times do |i|
        process items[i + 1] if i + 1 < items.size
      end
    CODE
  end

  it "does not flag a next-guard on the boundary" do
    guard_issues(Awesome::Guards::IndexLookahead, <<-CODE).should be_empty
      (0...rows.size).each do |j|
        next if j == rows.size - 1
        compare rows[j], rows[j + 1]
      end
    CODE
  end

  it "does not flag an adjusted range end" do
    guard_issues(Awesome::Guards::IndexLookahead, <<-CODE).should be_empty
      (0...rows.size - 1).each do |j|
        compare rows[j], rows[j + 1]
      end
    CODE
  end

  it "does not flag i - 1" do
    guard_issues(Awesome::Guards::IndexLookahead, <<-CODE).should be_empty
      (1...rows.size).each do |j|
        compare rows[j], rows[j - 1]
      end
    CODE
  end

  it "does not flag indexing a different collection" do
    guard_issues(Awesome::Guards::IndexLookahead, <<-CODE).should be_empty
      others.size.times do |i|
        process items[i + 1]
      end
    CODE
  end
end
