require "./spec_helper"

describe Awesome::Guards::SelfSizeIndex do
  it "flags indexing by the receiver's own size" do
    issues = guard_issues(Awesome::Guards::SelfSizeIndex, <<-CODE)
      last = items[items.size]
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain("size - 1")
  end

  it "flags an ivar receiver" do
    issues = guard_issues(Awesome::Guards::SelfSizeIndex, <<-CODE)
      def last
        @items[@items.size]
      end
    CODE
    issues.size.should eq(1)
  end

  it "flags the size through a local alias" do
    issues = guard_issues(Awesome::Guards::SelfSizeIndex, <<-CODE)
      n = rows.size
      tail = rows[n]
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(2)
    issues[0].message.should contain("line 1")
  end

  it "does not flag the nilable []? form" do
    guard_issues(Awesome::Guards::SelfSizeIndex, <<-CODE).should be_empty
      beyond = items[items.size]?
    CODE
  end

  it "does not flag size minus one" do
    guard_issues(Awesome::Guards::SelfSizeIndex, <<-CODE).should be_empty
      last = items[items.size - 1]
    CODE
  end

  it "does not flag indexing by another collection's size" do
    guard_issues(Awesome::Guards::SelfSizeIndex, <<-CODE).should be_empty
      first = items[others.size]
    CODE
  end

  it "does not flag an alias that was reassigned" do
    guard_issues(Awesome::Guards::SelfSizeIndex, <<-CODE).should be_empty
      n = rows.size
      n -= 1
      last = rows[n]
    CODE
  end

  it "does not flag an alias indexing a different receiver" do
    guard_issues(Awesome::Guards::SelfSizeIndex, <<-CODE).should be_empty
      n = rows.size
      first = items[n]
    CODE
  end

  it "does not flag a plain index" do
    guard_issues(Awesome::Guards::SelfSizeIndex, <<-CODE).should be_empty
      x = items[0]
      y = items[i]
    CODE
  end
end
