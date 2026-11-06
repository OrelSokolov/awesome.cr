require "./spec_helper"

describe Awesome::Guards::LongParameterList do
  it "flags a def crossing the threshold" do
    issues = guard_issues(Awesome::Guards::LongParameterList, <<-CODE)
      class Mailer
        def send(to, from, subject, body, cc, bcc, reply_to, attachments)
        end
      end
      CODE
    issues.size.should eq(1)
    issues[0].line.should be > 0
    issues[0].message.should contain("Mailer#send takes 8 parameters")
    issues[0].message.should contain("threshold: 7")
  end

  it "labels top-level defs by name and counts initialize too" do
    issues = guard_issues(Awesome::Guards::LongParameterList, <<-CODE)
      def help(a, b, c, d, e, f, g, h)
      end

      class Cfg
        def initialize(a, b, c, d, e, f, g, h)
        end
      end
      CODE
    issues.size.should eq(2)
    issues[0].message.should contain("help takes 8 parameters")
    issues[1].message.should contain("Cfg#initialize takes 8 parameters")
  end

  it "does not count the block argument and leaves short defs alone" do
    issues = guard_issues(Awesome::Guards::LongParameterList, <<-CODE)
      class Each
        def run(a, b, c, &block)
        end
      end
      CODE
    issues.should be_empty
  end

  it "counts self-methods and methods in structs and modules" do
    issues = guard_issues(Awesome::Guards::LongParameterList, <<-CODE)
      struct Point
        def move(x1, y1, x2, y2, x3, y3, x4, y4)
        end
      end
      CODE
    issues.size.should eq(1)
    issues[0].message.should contain("Point#move takes 8 parameters")
  end

  it "honours the configured threshold" do
    code = "class Trio\n  def run(a, b, c)\n  end\nend\n"
    guard_issues(Awesome::Guards::LongParameterList, code).should be_empty
    yaml = "LongParameterList:\n  max_params: 2\n"
    issues = guard_issues(Awesome::Guards::LongParameterList, code, yaml)
    issues.size.should eq(1)
    issues[0].message.should contain("threshold: 2")
  end
end
