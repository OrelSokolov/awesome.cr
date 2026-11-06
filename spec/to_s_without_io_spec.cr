require "./spec_helper"

describe Awesome::Guards::ToSWithoutIo do
  it "flags a zero-arg to_s" do
    issues = guard_issues(Awesome::Guards::ToSWithoutIo, <<-CODE)
      def to_s
        "\#{@x}"
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain("to_s(io : IO)")
  end

  it "flags a to_s with a return type annotation" do
    issues = guard_issues(Awesome::Guards::ToSWithoutIo, <<-CODE)
      struct Point
        def to_s : String
          "\#{@x}:\#{@y}"
        end
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(2)
  end

  it "flags an abstract zero-arg to_s" do
    issues = guard_issues(Awesome::Guards::ToSWithoutIo, <<-CODE)
      abstract class Shape
        abstract def to_s
      end
    CODE
    issues.size.should eq(1)
  end

  it "does not flag the io form" do
    guard_issues(Awesome::Guards::ToSWithoutIo, <<-CODE).should be_empty
      def to_s(io : IO)
        io << @x
      end
    CODE
  end

  it "does not flag other method names" do
    guard_issues(Awesome::Guards::ToSWithoutIo, <<-CODE).should be_empty
      def inspect
        "\#{@x}"
      end

      def to_str
        "\#{@x}"
      end
    CODE
  end

  it "respects check_to_s: false" do
    guard_issues(Awesome::Guards::ToSWithoutIo, <<-CODE, <<-YAML).should be_empty
      def to_s
        "\#{@x}"
      end
    CODE
      ToSWithoutIo:
        check_to_s: false
    YAML
  end
end
