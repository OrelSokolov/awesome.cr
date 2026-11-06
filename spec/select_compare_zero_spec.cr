require "./spec_helper"

describe Awesome::Guards::SelectCompareZero do
  it "flags select { … }.size == 0" do
    issues = guard_issues(Awesome::Guards::SelectCompareZero, <<-CODE)
      return if items.select { |item| item.invalid? }.size == 0
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain("none?")
  end

  it "flags select { … }.size > 0" do
    issues = guard_issues(Awesome::Guards::SelectCompareZero, <<-CODE)
      proceed if items.select { |item| item.urgent? }.size > 0
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("any?")
  end

  it "flags select { … }.size >= 1" do
    issues = guard_issues(Awesome::Guards::SelectCompareZero, <<-CODE)
      proceed if items.select { |item| item.urgent? }.size >= 1
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("any?")
  end

  it "flags select { … }.empty?" do
    issues = guard_issues(Awesome::Guards::SelectCompareZero, <<-CODE)
      return if items.select { |item| item.invalid? }.empty?
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("none?")
  end

  it "does not flag plain size comparisons" do
    guard_issues(Awesome::Guards::SelectCompareZero, <<-CODE).should be_empty
      return if items.size == 0
      proceed if items.size > 0
      return if items.empty?
    CODE
  end

  it "does not flag comparisons with other numbers" do
    guard_issues(Awesome::Guards::SelectCompareZero, <<-CODE).should be_empty
      return if items.select { |item| item.invalid? }.size == 1
      proceed if items.select { |item| item.urgent? }.size >= 2
    CODE
  end

  it "does not flag map { … }.size == 0 (different fix)" do
    guard_issues(Awesome::Guards::SelectCompareZero, <<-CODE).should be_empty
      return if items.map { |item| item.name }.size == 0
    CODE
  end

  it "does not flag select without a block" do
    guard_issues(Awesome::Guards::SelectCompareZero, <<-CODE).should be_empty
      return if items.select(expected).size == 0
    CODE
  end
end
