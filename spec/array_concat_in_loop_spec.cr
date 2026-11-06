require "./spec_helper"

describe Awesome::Guards::ArrayConcatInLoop do
  it "flags += with an array literal in a loop" do
    issues = guard_issues(Awesome::Guards::ArrayConcatInLoop, <<-CODE)
      acc = [] of Int32
      items.each do |item|
        acc += [item]
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(3)
    issues[0].message.should contain("<<")
  end

  it "flags the spelled-out acc = acc + [x] form" do
    issues = guard_issues(Awesome::Guards::ArrayConcatInLoop, <<-CODE)
      acc = [] of Int32
      10.times do |i|
        acc = acc + [i]
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(3)
  end

  it "flags += on an instance variable" do
    issues = guard_issues(Awesome::Guards::ArrayConcatInLoop, <<-CODE)
      while line = input.gets
        @chunks += [line]
      end
    CODE
    issues.size.should eq(1)
  end

  it "does not flag in-place << appends" do
    guard_issues(Awesome::Guards::ArrayConcatInLoop, <<-CODE).should be_empty
      acc = [] of Int32
      items.each do |item|
        acc << item
      end
    CODE
  end

  it "does not flag += outside loops" do
    guard_issues(Awesome::Guards::ArrayConcatInLoop, <<-CODE).should be_empty
      acc = [1]
      acc += [2]
    CODE
  end

  it "does not flag number += in a loop" do
    guard_issues(Awesome::Guards::ArrayConcatInLoop, <<-CODE).should be_empty
      total = 0
      items.each do |item|
        total += item.qty
      end
    CODE
  end

  it "does not flag concat onto a different variable" do
    guard_issues(Awesome::Guards::ArrayConcatInLoop, <<-CODE).should be_empty
      a = [1]
      b = [2]
      items.each do
        a = b + [3]
      end
    CODE
  end
end
