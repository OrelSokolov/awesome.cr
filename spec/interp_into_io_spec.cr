require "./spec_helper"

describe Awesome::Guards::InterpIntoIo do
  it "flags io << with an interpolation" do
    issues = guard_issues(Awesome::Guards::InterpIntoIo, <<-CODE)
      io << "user=\#{user.name} id=\#{user.id}"
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain("io <<")
  end

  it "flags puts with an interpolation" do
    issues = guard_issues(Awesome::Guards::InterpIntoIo, <<-CODE)
      puts "x=\#{x}"
    CODE
    issues.size.should eq(1)
  end

  it "flags print and explicit io.puts receivers" do
    issues = guard_issues(Awesome::Guards::InterpIntoIo, <<-CODE)
      print "a\#{b}"
      stderr.puts "c\#{d}"
    CODE
    issues.size.should eq(2)
  end

  it "flags an _io-suffixed receiver" do
    issues = guard_issues(Awesome::Guards::InterpIntoIo, <<-CODE)
      response_io << "status=\#{status}"
    CODE
    issues.size.should eq(1)
  end

  it "does not flag plain string parts appended separately" do
    guard_issues(Awesome::Guards::InterpIntoIo, <<-CODE).should be_empty
      io << "user=" << user.name
    CODE
  end

  it "does not flag a literal-only string" do
    guard_issues(Awesome::Guards::InterpIntoIo, <<-CODE).should be_empty
      io << "plain"
      puts "static"
    CODE
  end

  it "does not flag << on a non-IO receiver" do
    guard_issues(Awesome::Guards::InterpIntoIo, <<-CODE).should be_empty
      errors << "bad \#{value}"
      acc = [] of String
      acc << "item \#{value}"
    CODE
  end
end
