require "./spec_helper"
require "file_utils"

describe Awesome::Guard do
  it "classifies guards into kinds" do
    {"SelfSortReassign", "ArrayShiftInLoop", "MapFlatten",
     "StringConcatInLoop", "UnusedIndex"}.each do |name|
      Awesome::Guard.all.find { |g| g.name == name }.not_nil!.kind.should eq("speed")
    end
    {"MemoryLeak", "DoubleFree", "FileReadLines", "NilableStructField",
     "BoolBitmask", "StructurePacking"}.each do |name|
      Awesome::Guard.all.find { |g| g.name == name }.not_nil!.kind.should eq("memory")
    end
  end
end

describe Awesome::Runner do
  it "runs only speed guards when kind is speed" do
    dir = File.join(Dir.tempdir, "awesome_cli_#{Random.new.hex(6)}")
    Dir.mkdir_p(dir)
    File.write(File.join(dir, "bad.cr"), <<-CODE)
      words = lines.map(&.split).flatten
      struct Bad
        getter a : UInt8
        getter b : Int64
        getter c : UInt8
      end
    CODE

    config = Awesome::Config.new
    all = Awesome::Runner.new(config).run([dir])
    all.issues.size.should eq(2)

    speed = Awesome::Runner.new(config, kind: "speed").run([dir])
    speed.issues.map(&.guard).should eq(["MapFlatten"])

    memory = Awesome::Runner.new(config, kind: "memory").run([dir])
    memory.issues.map(&.guard).should eq(["StructurePacking"])
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end

describe Awesome::CLI do
  it "dispatches speed, memory and smell commands" do
    dir = File.join(Dir.tempdir, "awesome_cli_#{Random.new.hex(6)}")
    Dir.mkdir_p(dir)
    File.write(File.join(dir, "bad.cr"), "words = lines.map(&.split).flatten\n")

    Awesome::CLI.run(["speed", dir]).should eq(1)
    Awesome::CLI.run(["memory", dir]).should eq(0)
    Awesome::CLI.run(["smell", dir]).should eq(0) # no smell guards yet
    Awesome::CLI.run([dir]).should eq(1)
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "handles options" do
    Awesome::CLI.run(["--version"]).should eq(0)
    Awesome::CLI.run(["--help"]).should eq(0)
    Awesome::CLI.run(["--bogus"]).should eq(2)
    Awesome::CLI.run(["--config"]).should eq(2)
    Awesome::CLI.run(["--only", "MapFlatten", "--version"]).should eq(0)
  end

  it "lists registered guards" do
    Awesome::CLI.run(["guards"]).should eq(0)
  end
end
