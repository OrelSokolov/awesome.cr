require "./spec_helper"

describe Awesome::Guards::HardcodedDependency do
  it "flags a project class constructed outside initialize" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-CODE])
      class Engine
        def run; end
      end

      class Car
        def start
          engine = Engine.new
          engine.run
        end
      end
      CODE
    issues.size.should eq(1)
    issues[0].line.should be > 0
    issues[0].message.should contain("Car constructs Engine.new")
    issues[0].message.should contain("Car#start")
  end

  it "flags constructions at class body level" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-CODE])
      class Repo
      end

      class App
        DEFAULT_REPO = Repo.new
      end
      CODE
    issues.size.should eq(1)
    issues[0].message.should contain("App class body")
  end

  it "anchors issues to the file the construction is in" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-ENGINE, <<-CAR])
      class Engine
        def run; end
      end
      ENGINE
      class Car
        def start
          engine = Engine.new
        end
      end
      CAR
    issues.size.should eq(1)
    issues[0].path.should eq("(test1)")
  end

  it "does not flag injections, value types and legitimate constructions" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-CODE])
      class Engine
        def run; end
      end

      class Car
        def initialize(@engine : Engine)   # injected
          @spare = Engine.new              # initialize — allowed
        end

        def build_fleet
          fleet = Array{Car.new(self)}     # polymorphic + whitelisted Array
        end

        def self.factory
          Car.new(Engine.new)              # factory class-method
        end

        def fail
          raise EngineError.new("boom")    # exception
        end

        def parse(raw)
          visitor = Parser.new(raw)        # nested type — own helper
        end

        private class Parser
          def initialize(@raw : String); end
        end

        def draw                           # project struct — value object
          Vec.new(1, 2)
        end
      end

      struct Vec
        def initialize(@x : Int32, @y : Int32); end
      end

      struct Point
        def initialize(@x : Int32); end

        def twin
          Point.new(@x)                    # structs carry data, not collaborators
        end
      end
      CODE
    issues.should be_empty
  end

  it "stays silent about external types by default" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-CODE])
      class Car
        def start
          engine = Egui::Pos2.new(1, 2)    # external binding — data plumbing
        end
      end
      CODE
    issues.should be_empty
  end

  it "flags external types when flag_externals is on" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-CODE], <<-YAML)
      class Car
        def start
          client = HTTP::Client.new("example.com")
        end
      end
      CODE
      HardcodedDependency:
        flag_externals: true
      YAML
    issues.size.should eq(1)
    issues[0].message.should contain("Car constructs HTTP::Client.new")
  end

  it "respects the allowed whitelist by path and namespace" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-CODE], <<-YAML)
      class Car
        def start
          engine = MessageBus.new
          engine.start
        end
      end
      CODE
      HardcodedDependency:
        flag_externals: true
        allowed: [MessageBus]
      YAML
    issues.should be_empty
  end

  it "requires min_dependencies hits per class before firing" do
    code = [<<-CODE]
      class First
      end

      class Second
      end

      class A
        def x
          First.new
        end
      end

      class B
        def x
          Second.new
        end
      end
      CODE
    yaml = <<-YAML
      HardcodedDependency:
        min_dependencies: 2
      YAML
    guard_project_issues(Awesome::Guards::HardcodedDependency, code, yaml).should be_empty
    guard_project_issues(Awesome::Guards::HardcodedDependency, code).size.should eq(2)
  end
end
