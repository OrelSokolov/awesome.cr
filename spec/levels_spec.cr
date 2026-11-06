require "./spec_helper"
require "file_utils"

# Check levels: vibecoder (features first, don't break on first run) <
# senior (long-life code, readability-neutral best practices — the
# default) < psycho (readability traded for micro-wins, experiments or
# hard requirements only). A run at level N executes guards at level N
# or below; an explicit `enabled:` in awesome.yml overrides the level.
describe "check levels" do
  it "assigns levels to guards" do
    level_of = ->(name : String) do
      Awesome::Guard.all.find { |g| g.name == name }.not_nil!.level
    end
    {"MemoryLeak", "DoubleFree"}.each do |name|
      level_of.call(name).should eq("vibecoder")
    end
    {"InterpIntoIo", "SelfSortReassign"}.each do |name|
      level_of.call(name).should eq("psycho")
    end
    # Guards without an explicit LEVEL default to senior.
    {"MapFlatten", "GodClass", "FileReadLines"}.each do |name|
      level_of.call(name).should eq("senior")
    end
    Awesome::Guard::DEFAULT_LEVEL.should eq("senior")
  end

  it "runs guards at or below the selected level" do
    dir = File.join(Dir.tempdir, "awesome_levels_#{Random.new.hex(6)}")
    Dir.mkdir_p(dir)
    File.write(File.join(dir, "bad.cr"), %(puts "a\#{b}c"\n))

    config = Awesome::Config.new
    default = Awesome::Runner.new(config).run([dir])
    default.issues.should be_empty # senior default skips psycho guards

    psycho = Awesome::Runner.new(config, level: "psycho").run([dir])
    psycho.issues.map(&.guard).should eq(["InterpIntoIo"])

    vibecoder = Awesome::Runner.new(config, level: "vibecoder").run([dir])
    vibecoder.issues.should be_empty
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "lets an explicit enabled override the level in both directions" do
    dir = File.join(Dir.tempdir, "awesome_levels_#{Random.new.hex(6)}")
    Dir.mkdir_p(dir)
    File.write(File.join(dir, "bad.cr"), %(puts "a\#{b}c"\n))

    opted_in = Awesome::Config.from_yaml(<<-YAML)
      guards:
        InterpIntoIo:
          enabled: true
      YAML
    Awesome::Runner.new(opted_in).run([dir]).issues.map(&.guard).should eq(["InterpIntoIo"])

    silenced = Awesome::Config.from_yaml(<<-YAML)
      level: psycho
      guards:
        InterpIntoIo:
          enabled: false
      YAML
    Awesome::Runner.new(silenced).run([dir]).issues.should be_empty
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "parses the level from awesome.yml" do
    Awesome::Config.from_yaml("level: psycho\n").level.should eq("psycho")
    Awesome::Config.new.level.should be_nil
  end

  it "rejects unknown levels from the CLI" do
    Awesome::CLI.run(["--level", "bogus"]).should eq(2)
    Awesome::CLI.run(["--level", "psycho", "--version"]).should eq(0)
  end
end
