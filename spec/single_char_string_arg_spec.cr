require "./spec_helper"

describe Awesome::Guards::SingleCharStringArg do
  it "flags split with a single-char separator" do
    issues = guard_issues(Awesome::Guards::SingleCharStringArg, <<-CODE)
      parts = path.split("/")
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain("split('/')")
  end

  it "flags includes?, starts_with? and ends_with?" do
    issues = guard_issues(Awesome::Guards::SingleCharStringArg, <<-CODE)
      ok = text.includes?("*")
      ok = text.starts_with?("/")
      ok = text.ends_with?(",")
    CODE
    issues.size.should eq(3)
  end

  it "flags replace, sub and gsub with single-char pairs" do
    issues = guard_issues(Awesome::Guards::SingleCharStringArg, <<-CODE)
      a = text.replace("a", "b")
      b = text.sub("a", "b")
      c = text.gsub("a", "b")
    CODE
    issues.size.should eq(3)
    issues[0].message.should contain("('a', 'b')")
  end

  it "does not flag multi-character strings" do
    guard_issues(Awesome::Guards::SingleCharStringArg, <<-CODE).should be_empty
      parts = path.split(", ")
      a = text.gsub("ab", "cd")
      ok = text.includes?("ab")
    CODE
  end

  it "does not flag mixed single/multi pairs" do
    guard_issues(Awesome::Guards::SingleCharStringArg, <<-CODE).should be_empty
      a = text.gsub("a", "many")
      b = text.gsub("many", "b")
    CODE
  end

  it "does not flag extra arguments" do
    guard_issues(Awesome::Guards::SingleCharStringArg, <<-CODE).should be_empty
      parts = path.split("/", 2)
    CODE
  end

  it "does not flag non-literal arguments" do
    guard_issues(Awesome::Guards::SingleCharStringArg, <<-CODE).should be_empty
      parts = path.split(sep)
      a = text.gsub("a", replacement)
    CODE
  end
end
