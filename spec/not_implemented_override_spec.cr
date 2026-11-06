require "./spec_helper"

describe Awesome::Guards::NotImplementedOverride do
  it "flags a raise-only override of a parent's concrete method" do
    issues = guard_project_issues(Awesome::Guards::NotImplementedOverride, [<<-CODE])
      class Shape
        def area
          0
        end
      end

      class Line < Shape
        def area
          raise NotImplementedError.new("lines have no area")
        end
      end
      CODE
    issues.size.should eq(1)
    issues[0].line.should be > 0
    issues[0].message.should contain("Line#area only raises NotImplementedError")
    issues[0].message.should contain("Shape#area is concrete")
    issues[0].message.should contain("can't stand where the parent stood")
  end

  it "pairs the parent across files and fires per def" do
    issues = guard_project_issues(Awesome::Guards::NotImplementedOverride, [
      "class Shape\n  def area\n    0\n  end\nend",
      "class Line < Shape\n  def area\n    raise NotImplementedError.new\n  end\nend",
    ])
    issues.size.should eq(1)
    issues[0].path.should eq("(test1)")
  end

  it "skips raise-only defs matching only an abstract parent def" do
    issues = guard_project_issues(Awesome::Guards::NotImplementedOverride, [<<-CODE])
      abstract class Store
        abstract def fetch(key)
      end

      class NullStore < Store
        def fetch(key)
          raise NotImplementedError.new("null store")
        end
      end
      CODE
    issues.should be_empty
  end

  it "skips external parents, non-overrides and plain raise strings" do
    issues = guard_project_issues(Awesome::Guards::NotImplementedOverride, [<<-CODE])
      class Weird < Kemal::Base # external parent — methods unknowable
        def handle
          raise NotImplementedError.new("nope")
        end
      end

      class Lone
        def solo_method
          raise NotImplementedError.new("no parent at all")
        end

        def string_raise
          raise "not implemented" # a String doesn't name the concept
        end
      end
      CODE
    issues.should be_empty
  end

  it "ignores bodies that do more than raise" do
    issues = guard_project_issues(Awesome::Guards::NotImplementedOverride, [<<-CODE])
      class Shape
        def area
          0
        end
      end

      class Lazy < Shape
        def area
          return 1 if @cached
          raise NotImplementedError.new("never reached in practice")
        end
      end
      CODE
    issues.should be_empty
  end

  it "reports the abstract_def_names index extension" do
    index = Awesome::Index.new([Awesome::Source.new("(t)", <<-CODE
      abstract class Base
        abstract def go : Nil
      end

      class Impl < Base
        def go : Nil
        end
      end
      CODE
    )])
    base = index.resolve("Base").not_nil!
    base.abstract_def_names.should eq(["go"])
    base.def_names.should eq(["go"])
    index.subclasses_of(base).first.def_names.should eq(["go"])
    index.subclasses_of(base).first.abstract_def_names.should be_empty
  end
end
