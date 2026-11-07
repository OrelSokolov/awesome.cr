require "./spec_helper"
require "file_utils"

describe Awesome::Guards::CliStdoutEpipe do
  it "flags a script with top-level output and no EPIPE handling" do
    issues = guard_project_issues(Awesome::Guards::CliStdoutEpipe, [<<-CODE])
      require "json"
      puts "report line 1"
      puts "report line 2"
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(2)
    issues[0].message.should contain("EPIPE")
  end

  it "flags a bare STDOUT append at top level" do
    issues = guard_project_issues(Awesome::Guards::CliStdoutEpipe, [<<-CODE])
      STDOUT << "done\\n"
    CODE
    issues.size.should eq(1)
  end

  it "does not flag output inside defs and blocks" do
    guard_project_issues(Awesome::Guards::CliStdoutEpipe, [<<-CODE]).should be_empty
      def report
        puts "line"
      end

      describe "spec" do
        puts "inside a block"
      end
    CODE
  end

  it "does not flag a file with no top-level output" do
    guard_project_issues(Awesome::Guards::CliStdoutEpipe, [<<-CODE]).should be_empty
      require "../src/tool"
      exit Tool::CLI.run(ARGV)
    CODE
  end

  it "does not flag the CRASH-001 fix: rescue IO::Error at the entry point" do
    guard_project_issues(Awesome::Guards::CliStdoutEpipe, [<<-CODE]).should be_empty
      require "../src/awesome"
      begin
        exit Awesome::CLI.run(ARGV)
      rescue e : IO::Error
        exit(e.os_error == Errno::EPIPE ? 0 : 1)
      end
    CODE
  end

  it "does not flag a Signal::PIPE trap" do
    guard_project_issues(Awesome::Guards::CliStdoutEpipe, [<<-CODE]).should be_empty
      require "../src/tool"
      Signal.trap(Signal::PIPE) { exit 0 }
      puts Tool.run
    CODE
  end

  it "flags a declared shard.yml binary without handling" do
    dir = File.join(Dir.tempdir, "awesome_epipe_#{Random.new.hex(6)}")
    Dir.mkdir_p(File.join(dir, "bin"))
    File.write(File.join(dir, "shard.yml"), <<-YAML)
      name: tool
      binaries:
        tool:
          main: bin/tool.cr
    YAML
    File.write(File.join(dir, "bin", "tool.cr"), "require \"../src/tool\"\nexit Tool::CLI.run(ARGV)\n")

    previous = Dir.current
    Dir.cd(dir)
    sources = [Awesome::Source.new("src/tool.cr", "class Tool; end")]
    issues = Awesome::Guards::CliStdoutEpipe.new
      .test_project(sources, Awesome::GuardConfig.new(nil))
    issues.size.should eq(1)
    issues[0].path.should eq("bin/tool.cr")
    issues[0].message.should contain("binary")
  ensure
    Dir.cd(previous) if previous
    FileUtils.rm_rf(dir) if dir
  end

  it "does not flag a declared binary that handles EPIPE" do
    dir = File.join(Dir.tempdir, "awesome_epipe_#{Random.new.hex(6)}")
    Dir.mkdir_p(File.join(dir, "bin"))
    File.write(File.join(dir, "shard.yml"), <<-YAML)
      name: tool
      binaries:
        tool:
          main: bin/tool.cr
    YAML
    File.write(File.join(dir, "bin", "tool.cr"), <<-CODE)
      require "../src/tool"
      begin
        exit Tool::CLI.run(ARGV)
      rescue e : IO::Error
        exit(e.os_error == Errno::EPIPE ? 0 : 1)
      end
    CODE

    previous = Dir.current
    Dir.cd(dir)
    sources = [Awesome::Source.new("src/tool.cr", "class Tool; end")]
    Awesome::Guards::CliStdoutEpipe.new
      .test_project(sources, Awesome::GuardConfig.new(nil)).should be_empty
  ensure
    Dir.cd(previous) if previous
    FileUtils.rm_rf(dir) if dir
  end

  it "checks a declared binary even when it is also in the collected set" do
    dir = File.join(Dir.tempdir, "awesome_epipe_#{Random.new.hex(6)}")
    Dir.mkdir_p(File.join(dir, "bin"))
    File.write(File.join(dir, "shard.yml"), <<-YAML)
      name: tool
      binaries:
        tool:
          main: bin/tool.cr
    YAML
    File.write(File.join(dir, "bin", "tool.cr"), "require \"../src/tool\"\nexit Tool::CLI.run(ARGV)\n")

    previous = Dir.current
    Dir.cd(dir)
    sources = [Awesome::Source.new("bin/tool.cr"), Awesome::Source.new("src/tool.cr", "class Tool; end")]
    issues = Awesome::Guards::CliStdoutEpipe.new
      .test_project(sources, Awesome::GuardConfig.new(nil))
    issues.size.should eq(1) # entry-flow check once, not script + binary twice
    issues[0].path.should eq("bin/tool.cr")
  ensure
    Dir.cd(previous) if previous
    FileUtils.rm_rf(dir) if dir
  end
end
