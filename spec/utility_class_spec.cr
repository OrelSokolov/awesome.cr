require "./spec_helper"

describe Awesome::Guards::UtilityClass do
  it "flags a class with only class methods" do
    issues = guard_issues(Awesome::Guards::UtilityClass, <<-CODE)
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
    issues = guard_issues(Awesome::Guards::UtilityClass, <<-CODE)
      module Registry
        def self.load(path)
        end
      end
      CODE
    issues.should be_empty
  end

  it "skips classes with any instance behaviour" do
    issues = guard_issues(Awesome::Guards::UtilityClass, <<-CODE)
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
    issues = guard_issues(Awesome::Guards::UtilityClass, <<-CODE)
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
    issues = guard_issues(Awesome::Guards::UtilityClass, <<-CODE)
      class Point
        def self.new(x, y)
          allocate
        end
      end
      CODE
    issues.should be_empty
  end

  it "keeps nested classes separate" do
    issues = guard_issues(Awesome::Guards::UtilityClass, <<-CODE)
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
end
