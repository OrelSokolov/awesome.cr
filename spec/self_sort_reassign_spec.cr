require "./spec_helper"

describe Awesome::Guards::SelfSortReassign do
  it "flags xs = xs.sort" do
    issues = guard_issues(Awesome::Guards::SelfSortReassign, <<-CODE)
      items = load_items
      items = items.sort
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(2)
    issues[0].message.should contain("sort!")
  end

  it "flags other reassignable methods" do
    %w(uniq reverse shuffle rotate).each do |meth|
      code = "items = load_items\nitems = items.#{meth}"
      issues = guard_issues(Awesome::Guards::SelfSortReassign, code)
      issues.size.should eq(1)
      issues[0].message.should contain("#{meth}!")
    end
  end

  it "keeps a comparator block out of the way" do
    issues = guard_issues(Awesome::Guards::SelfSortReassign, <<-CODE)
      items = load_items
      items = items.sort { |a, b| a.qty <=> b.qty }
    CODE
    issues.size.should eq(1)
  end

  it "does not flag sorting into a different variable" do
    guard_issues(Awesome::Guards::SelfSortReassign, <<-CODE).should be_empty
      sorted = items.sort
      items = other.sort
    CODE
  end

  it "does not flag the already-bang version" do
    guard_issues(Awesome::Guards::SelfSortReassign, <<-CODE).should be_empty
      items = load_items
      items.sort!
      items = items.sort!
    CODE
  end

  it "does not flag calls with arguments" do
    guard_issues(Awesome::Guards::SelfSortReassign, <<-CODE).should be_empty
      items = load_items
      items = items.rotate(2)
    CODE
  end
end
