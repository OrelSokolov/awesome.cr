require "./spec_helper"

describe Awesome::Guards::HardcodedDependency do
  it "flags a dependency constructed outside initialize" do
    issues = guard_issues(Awesome::Guards::HardcodedDependency, <<-CODE)
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
    issues = guard_issues(Awesome::Guards::HardcodedDependency, <<-CODE)
      class App
        DEFAULT_REPO = Repo.new
      end
      CODE
    issues.size.should eq(1)
    issues[0].message.should contain("App class body")
  end

  it "does not flag injections and legitimate constructions" do
    issues = guard_issues(Awesome::Guards::HardcodedDependency, <<-CODE)
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

  it "respects the allowed whitelist by path and namespace" do
    issues = guard_issues(Awesome::Guards::HardcodedDependency, <<-CODE, <<-YAML)
      class App
        def boot
          bus = MessageBus.new
          bus.start
        end
      end
      CODE
      HardcodedDependency:
        allowed: [MessageBus]
      YAML
    issues.should be_empty
  end

  it "requires min_dependencies hits per class before firing" do
    code = <<-CODE
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
    guard_issues(Awesome::Guards::HardcodedDependency, code, yaml).should be_empty
    guard_issues(Awesome::Guards::HardcodedDependency, code).size.should eq(2)
  end
end
