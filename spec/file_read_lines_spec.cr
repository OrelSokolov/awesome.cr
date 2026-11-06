require "./spec_helper"

describe Awesome::Guards::FileReadLines do
  it "flags File.read_lines" do
    issues = guard_issues(Awesome::Guards::FileReadLines, <<-CODE)
      File.read_lines(path).each do |line|
        process line
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain("each_line")
  end

  it "passes on File.each_line" do
    guard_issues(Awesome::Guards::FileReadLines, <<-CODE).should be_empty
      File.each_line(path) do |line|
        process line
      end
    CODE
  end

  it "ignores read_lines on other receivers" do
    guard_issues(Awesome::Guards::FileReadLines, <<-CODE).should be_empty
      response = client.read_lines
      io = conn.read_lines
    CODE
  end

  it "flags File.read_lines wherever it appears" do
    issues = guard_issues(Awesome::Guards::FileReadLines, <<-CODE)
      def load
        config = File.read_lines("/etc/app.conf")
        parse config
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(2)
  end
end
