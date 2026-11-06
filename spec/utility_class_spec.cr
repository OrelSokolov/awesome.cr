require "./spec_helper"

# Single snippet runs as a one-file project; an Array(String) is a
# multi-file project (one Source per string).
def utility_issues(code : String | Array(String), config_yaml : String? = nil) : Array(Awesome::Issue)
  codes = code.is_a?(String) ? [code] : code
  guard_project_issues(Awesome::Guards::UtilityClass, codes, config_yaml)
end

describe Awesome::Guards::UtilityClass do
  it "flags a class with only class methods" do
    issues = utility_issues(<<-CODE)
      class Registry
        def self.load(path)
        end

        def self.save(path, data)
        end
      end
      CODE
    issues.size.should eq(1)
    issues[0].line.should be > 0
    issues[0].message.should contain("Registry: all 2 methods are class methods")
    issues[0].message.should contain("make it a module")
  end

  it "does not flag a module — namespaces are the honest spelling" do
    issues = utility_issues(<<-CODE)
      module Registry
        def self.load(path)
        end
      end
      CODE
    issues.should be_empty
  end

  it "skips classes with any instance behaviour" do
    issues = utility_issues(<<-CODE)
      class WithInit
        def self.build
        end

        def initialize(@path)
        end
      end

      class WithDef
        def self.build
        end

        def load
        end
      end

      class WithGetter
        def self.build
        end

        getter path : String
      end

      class WithMacro
        def self.build
        end

        macro inherited
        end
      end
      CODE
    issues.should be_empty
  end

  it "skips subclasses, structs and empty classes" do
    issues = utility_issues(<<-CODE)
      class Base
        def load
        end
      end

      class Child < Base # inherited behaviour is unknowable
        def self.build
        end
      end

      struct Values # value types carry data, not roles
        def self.build
        end
      end

      class Hollow; end # nothing at all — not a namespace verdict
      CODE
    issues.should be_empty
  end

  it "skips def self.new factories — construction through them is meaningful" do
    issues = utility_issues(<<-CODE)
      class Point
        def self.new(x, y)
          allocate
        end
      end
      CODE
    issues.should be_empty
  end

  it "keeps nested classes separate" do
    issues = utility_issues(<<-CODE)
      class Outer
        def load
        end

        class Inner
          def self.build
          end
        end
      end
      CODE
    issues.size.should eq(1)
    issues[0].message.should contain("Inner")
  end

  it "does not flag a class whose reopening in another file adds instance behaviour" do
    issues = utility_issues([
      <<-CODE,
        class Registry
          def self.load(path)
          end

          def self.save(path, data)
          end
        end
      CODE
      <<-CODE,
        class Registry
          def helper # instance behaviour, added in another file
          end
        end
      CODE
    ])
    issues.should be_empty
  end

  it "does not flag a class that another file subclasses — module can't be inherited" do
    issues = utility_issues([
      <<-CODE,
        class Registry
          def self.load(path)
          end
        end
      CODE
      <<-CODE,
        class FastRegistry < Registry
          def find(x)
          end
        end
      CODE
    ])
    issues.should be_empty
  end
end
