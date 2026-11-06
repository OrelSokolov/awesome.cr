require "./spec_helper"
require "file_utils"

describe Awesome::Config do
  it "uses defaults without a config file" do
    config = Awesome::Config.new
    config.includes.should eq(Awesome::Config::DEFAULT_INCLUDE)
    config.excludes.should eq(Awesome::Config::DEFAULT_EXCLUDE)
    config.guard("StructurePacking").enabled?.should be_true
  end

  it "parses include/exclude and guard settings" do
    config = Awesome::Config.from_yaml(<<-YAML)
      include:
        - src/**/*.cr
      exclude:
        - vendor/**
      guards:
        StructurePacking:
          enabled: false
          check_extern: true
      YAML
    config.includes.should eq(["src/**/*.cr"])
    config.excludes.should eq(["vendor/**"])
    guard = config.guard("StructurePacking")
    guard.enabled?.should be_false
    guard.bool("check_extern", false).should be_true
  end

  it "falls back to defaults for unknown guards" do
    config = Awesome::Config.new
    config.guard("NoSuchGuard").enabled?.should be_true
  end
end

describe Awesome::Runner do
  it "runs the guard over a directory and reports the issue" do
    dir = File.join(Dir.tempdir, "awesome_spec_#{Random.new.hex(6)}")
    Dir.mkdir_p(File.join(dir, "src"))
    File.write(File.join(dir, "src", "bad.cr"), <<-CODE)
      struct Bad
        getter a : UInt8
        getter b : Int64
        getter c : UInt8
      end
    CODE

    config = Awesome::Config.new
    report = Awesome::Runner.new(config).run([dir])
    report.inspected.should eq(1)
    report.issues.size.should eq(1)
    report.awesome?.should be_false
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
