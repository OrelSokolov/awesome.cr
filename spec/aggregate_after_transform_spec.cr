require "./spec_helper"

describe Awesome::Guards::AggregateAfterTransform do
  it "flags map { … }.sum" do
    issues = guard_issues(Awesome::Guards::AggregateAfterTransform, <<-CODE)
      total = invoices.map { |inv| inv.amount }.sum
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain(".sum")
  end

  it "flags map { … }.size" do
    issues = guard_issues(Awesome::Guards::AggregateAfterTransform, <<-CODE)
      count = invoices.map { |inv| inv.amount }.size
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("invoices.size")
  end

  it "flags map { … }.empty?" do
    issues = guard_issues(Awesome::Guards::AggregateAfterTransform, <<-CODE)
      done = invoices.map { |inv| inv.amount }.empty?
    CODE
    issues.size.should eq(1)
  end

  it "flags the &.method shorthand form" do
    issues = guard_issues(Awesome::Guards::AggregateAfterTransform, <<-CODE)
      total = invoices.map(&.amount).sum
    CODE
    issues.size.should eq(1)
  end

  it "does not flag a direct sum with a block" do
    guard_issues(Awesome::Guards::AggregateAfterTransform, <<-CODE).should be_empty
      total = invoices.sum { |inv| inv.amount }
    CODE
  end

  it "does not flag plain receiver aggregates" do
    guard_issues(Awesome::Guards::AggregateAfterTransform, <<-CODE).should be_empty
      count = invoices.size
      done = invoices.empty?
    CODE
  end

  it "does not flag select { … }.size (SelectCompareZero territory)" do
    guard_issues(Awesome::Guards::AggregateAfterTransform, <<-CODE).should be_empty
      count = invoices.select { |inv| inv.amount > 0 }.size
    CODE
  end
end
