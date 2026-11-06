require "./spec_helper"

describe Awesome::Guards::StringConcatInLoop do
  it "flags += with a string literal in a while loop" do
    issues = guard_issues(Awesome::Guards::StringConcatInLoop, <<-CODE)
      text = ""
      while line = reader.gets
        text += line.chomp
        text += "\\n"
      end
    CODE
    # only the literal side is flagged (line.chomp is not a string node)
    issues.size.should eq(1)
    issues[0].line.should eq(4)
    issues[0].message.should contain("IO::Memory")
  end

  it "flags += with an interpolation" do
    issues = guard_issues(Awesome::Guards::StringConcatInLoop, <<-CODE)
      text = ""
      items.each do |item|
        text += "\#{item.name}: \#{item.qty}"
      end
    CODE
    issues.size.should eq(1)
  end

  it "flags the spelled-out s = s + lit form" do
    issues = guard_issues(Awesome::Guards::StringConcatInLoop, <<-CODE)
      text = ""
      10.times do
        text = text + "x"
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(3)
  end

  it "does not flag number += in a loop" do
    guard_issues(Awesome::Guards::StringConcatInLoop, <<-CODE).should be_empty
      total = 0
      items.each do |item|
        total += item.qty
      end
    CODE
  end

  it "does not flag string += outside loops" do
    guard_issues(Awesome::Guards::StringConcatInLoop, <<-CODE).should be_empty
      text = "a"
      text += "b"
    CODE
  end

  it "does not flag array << appends" do
    guard_issues(Awesome::Guards::StringConcatInLoop, <<-CODE).should be_empty
      acc = [] of String
      items.each do |item|
        acc << item.name
      end
    CODE
  end

  it "does not flag concat onto a different variable" do
    guard_issues(Awesome::Guards::StringConcatInLoop, <<-CODE).should be_empty
      a = "a"
      b = "b"
      10.times do
        a = b + "x"
      end
    CODE
  end
end
