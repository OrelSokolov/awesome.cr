require "./spec_helper"

# Single snippet runs as a one-file project; an Array(String) is a
# multi-file project (one Source per string).
def to_s_issues(code : String | Array(String), config_yaml : String? = nil) : Array(Awesome::Issue)
  codes = code.is_a?(String) ? [code] : code
  guard_project_issues(Awesome::Guards::ToSWithoutIo, codes, config_yaml)
end

describe Awesome::Guards::ToSWithoutIo do
  it "flags a zero-arg to_s" do
    issues = to_s_issues(<<-CODE)
      def to_s
        "\#{@x}"
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain("to_s(io : IO)")
  end

  it "flags a to_s with a return type annotation" do
    issues = to_s_issues(<<-CODE)
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
    issues = to_s_issues(<<-CODE)
      abstract class Shape
        abstract def to_s
      end
    CODE
    issues.size.should eq(1)
  end

  it "does not flag the io form" do
    to_s_issues(<<-CODE).should be_empty
      def to_s(io : IO)
        io << @x
      end
    CODE
  end

  it "does not flag other method names" do
    to_s_issues(<<-CODE).should be_empty
      def inspect
        "\#{@x}"
      end

      def to_str
        "\#{@x}"
      end
    CODE
  end

  it "respects check_to_s: false" do
    to_s_issues(<<-CODE, <<-YAML).should be_empty
      def to_s
        "\#{@x}"
      end
    CODE
      ToSWithoutIo:
        check_to_s: false
    YAML
  end

  it "does not flag a class that also defines a to_s overload with arguments" do
    to_s_issues(<<-CODE).should be_empty
      class Point
        def to_s
          "(\#{@x}, \#{@y})"
        end

        def to_s(io : IO)
          io << to_s # the io path does run the zero-arg form
        end
      end
    CODE
  end

  it "does not flag when the io overload arrives by reopening in another file" do
    to_s_issues([
      <<-CODE,
        class Point
          def to_s
            "(\#{@x}, \#{@y})"
          end
        end
      CODE
      <<-CODE,
        class Point
          def to_s(io : IO)
            io << to_s
          end
        end
      CODE
    ]).should be_empty
  end
end
