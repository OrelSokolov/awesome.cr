require "./spec_helper"

describe Awesome::Guards::GodClass do
  it "flags a class crossing either threshold" do
    properties = (1..10).map { |i| "  property ivar#{i} : Int32" }.join('\n')
    issues = guard_issues(Awesome::Guards::GodClass, <<-CODE)
      class Blob
      #{properties}
        def poke; end
      end
      CODE
    issues.size.should eq(1)
    issues[0].line.should be > 0
    issues[0].message.should contain("Blob: 1 method and 10 ivars")
    issues[0].message.should contain("thresholds: 25 methods / 10 ivars")
  end

  it "counts methods, abstract methods and self-methods alike" do
    defs = (1..25).map { |i| "  def m#{i}; end" }.join('\n')
    issues = guard_issues(Awesome::Guards::GodClass, <<-CODE)
      class Busy
      #{defs}
      end
      CODE
    issues.size.should eq(1)
    issues[0].message.should contain("25 methods")
  end

  it "counts ivars declared, assigned and macro-declared once each" do
    issues = guard_issues(Awesome::Guards::GodClass, <<-CODE)
      class State
        @a : Int32
        @b = 1

        def touch
          @c = 2
          @a += 1
        end

        getter d : Bool
        property :e
      end
      CODE
    issues.should be_empty # 5 unique ivars — under the threshold
  end

  it "keeps nested and sibling classes separate and skips structs and modules" do
    issues = guard_issues(Awesome::Guards::GodClass, <<-CODE)
      module Wide
        def m1; end
        def m2; end
      end

      struct Packet
        @a : Int32
        @b : Int32
      end

      class Outer
        def om; end

        class Inner
          def im1; end
          def im2; end
        end
      end
      CODE
    issues.should be_empty
  end

  it "honours configured thresholds" do
    code = "class Small\n  def a; end\n  def b; end\nend\n"
    guard_issues(Awesome::Guards::GodClass, code).should be_empty
    yaml = "GodClass:\n  max_methods: 2\n"
    issues = guard_issues(Awesome::Guards::GodClass, code, yaml)
    issues.size.should eq(1)
    issues[0].message.should contain("Small: 2 methods and 0 ivars")
  end
end
