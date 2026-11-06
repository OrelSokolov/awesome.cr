require "./spec_helper"

describe Awesome::Guards::BoolFlagParameter do
  it "flags a Bool param fed both literals at call sites" do
    issues = guard_project_issues(Awesome::Guards::BoolFlagParameter, [<<-CODE])
      class Sync
        def run(force : Bool)
        end
      end

      Sync.new.run(true)
      Sync.new.run(false)
      CODE
    issues.size.should eq(1)
    issues[0].line.should be > 0
    issues[0].message.should contain("run's force is a flag argument")
    issues[0].message.should contain("both true and false")
  end

  it "pairs named-argument literals with the param name" do
    issues = guard_project_issues(Awesome::Guards::BoolFlagParameter, [<<-CODE]
      class Job
        def retries(exhausted : Bool)
        end
      end

      Job.new.retries(exhausted: true)
      Job.new.retries(exhausted: false)
      CODE
    )
    issues.size.should eq(1)
    issues[0].message.should contain("retries' exhausted is a flag argument")
  end

  it "requires both literals — one-sided Bool params are legitimate" do
    issues = guard_project_issues(Awesome::Guards::BoolFlagParameter, [<<-CODE]
      class Sync
        def run(force : Bool)
        end
      end

      Sync.new.run(true)
      Sync.new.run(quiet?)
      CODE
    )
    issues.should be_empty
  end

  it "matches call sites across files" do
    issues = guard_project_issues(Awesome::Guards::BoolFlagParameter, [
      "class Sync\n  def run(force : Bool)\n  end\nend",
      "Sync.new.run(true)",
      "Sync.new.run(false)",
    ])
    issues.size.should eq(1)
    issues[0].path.should eq("(test0)")
  end

  it "skips ambiguous names, initialize defs, operators and non-Bool restrictions" do
    issues = guard_project_issues(Awesome::Guards::BoolFlagParameter, [<<-CODE]
      class A
        def run(force : Bool) # another `run` exists below — unattributable
        end
      end

      class B
        def run(force : Bool)
        end
      end

      class Cfg
        def initialize(verbose : Bool) # .new(true) can't be attributed
        end
      end

      class Ops
        def ==(other : Bool) # operator — not a flag
        end
      end

      class Loose
        def load(mode) # no Bool restriction — not provably a flag
        end
      end

      A.new.run(true)
      B.new.run(false)
      Cfg.new(true)
      Cfg.new(false)
      x = 1 == true
      y = 1 == false
      Loose.new.load(true)
      Loose.new.load(false)
      CODE
    )
    issues.should be_empty
  end

  it "never flags a parameter named default — a value, not a branch" do
    issues = guard_project_issues(Awesome::Guards::BoolFlagParameter, [<<-CODE]
      class Cfg
        def bool(key, default : Bool) # config readers flip it freely
        end
      end

      Cfg.new.bool("enabled", true)
      Cfg.new.bool("strict", false)
      CODE
    )
    issues.should be_empty
  end

  it "honours the allowed list of param names" do
    code = "class Sync\n  def run(force : Bool)\n  end\nend\n\nSync.new.run(true)\nSync.new.run(false)\n"
    guard_project_issues(Awesome::Guards::BoolFlagParameter, [code]).size.should eq(1)
    yaml = "BoolFlagParameter:\n  allowed: [force]\n"
    guard_project_issues(Awesome::Guards::BoolFlagParameter, [code], yaml).should be_empty
  end
end
