require "./spec_helper"
require "./support/empty_guard"
require "./support/project_probe_guard"
require "file_utils"

describe "per-project pass" do
  it "base guard defaults report nothing" do
    guard_issues(EmptyGuard, "class A; def a; end; end").should be_empty
    guard_project_issues(EmptyGuard, ["class A; def a; end; end"]).should be_empty
  end

  it "calls test_project once per guard with the collected sources" do
    dir = File.join(Dir.tempdir, "awesome_project_#{Random.new.hex(6)}")
    Dir.mkdir_p(File.join(dir, "nested"))
    File.write(File.join(dir, "a.cr"), "class A; end\n")
    File.write(File.join(dir, "nested", "b.cr"), "class B < A; end\n")

    Awesome::Guard.registered << ProjectProbeGuard
    ProjectProbeGuard.calls.clear
    Awesome::Runner.new(Awesome::Config.new).run([dir])
    ProjectProbeGuard.calls.size.should eq(1)
    ProjectProbeGuard.calls.first.size.should eq(2)
  ensure
    Awesome::Guard.registered.delete(ProjectProbeGuard)
    FileUtils.rm_rf(dir) if dir
  end

  it "keeps excluded paths (lib by default) out of the project set" do
    dir = File.join(Dir.tempdir, "awesome_project_#{Random.new.hex(6)}")
    Dir.mkdir_p(File.join(dir, "lib"))
    File.write(File.join(dir, "a.cr"), "class A; end\n")
    File.write(File.join(dir, "lib", "dep.cr"), "class Dep; end\n")

    Awesome::Guard.registered << ProjectProbeGuard
    ProjectProbeGuard.calls.clear
    # lib/** is excluded relative to the working directory, so scope the
    # exclude to the temp dir the same way collect_files globs it:
    config = Awesome::Config.new(excludes: ["#{dir}/lib/**"])
    Awesome::Runner.new(config).run([dir])
    Awesome::Config::DEFAULT_EXCLUDE.should contain("lib/**")
    ProjectProbeGuard.calls.first.should_not contain(File.join(dir, "lib", "dep.cr"))
    ProjectProbeGuard.calls.first.should contain(File.join(dir, "a.cr"))
  ensure
    Awesome::Guard.registered.delete(ProjectProbeGuard)
    FileUtils.rm_rf(dir) if dir
  end

  it "skips sources that failed to parse" do
    dir = File.join(Dir.tempdir, "awesome_project_#{Random.new.hex(6)}")
    Dir.mkdir_p(dir)
    File.write(File.join(dir, "a.cr"), "class A; end\n")
    File.write(File.join(dir, "broken.cr"), "class B {{{\n")

    Awesome::Guard.registered << ProjectProbeGuard
    ProjectProbeGuard.calls.clear
    Awesome::Runner.new(Awesome::Config.new).run([dir])
    ProjectProbeGuard.calls.first.should eq([File.join(dir, "a.cr")])
  ensure
    Awesome::Guard.registered.delete(ProjectProbeGuard)
    FileUtils.rm_rf(dir) if dir
  end
end
