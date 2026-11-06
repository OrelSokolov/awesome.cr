require "./spec_helper"

def raise_in_lib_callback_issues(code : String, config_yaml : String? = nil) : Array(Awesome::Issue)
  guard_issues(Awesome::Guards::RaiseInLibCallback, code, config_yaml)
end

describe Awesome::Guards::RaiseInLibCallback do
  it "flags a raise inside a proc passed to a lib fun" do
    issues = raise_in_lib_callback_issues(<<-CODE)
      lib LibWatch
        fun each(cb : Int32 -> Void) : Void
      end

      LibWatch.each(->(row : Int32) {
        raise "row is corrupt"
      })
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(6)
    issues[0].message.should contain("LibWatch.each")
  end

  it "flags reraise the same way" do
    issues = raise_in_lib_callback_issues(<<-CODE)
      lib LibWatch
        fun each(cb : Int32 -> Void) : Void
      end

      LibWatch.each(->(row : Int32) {
        reraise
      })
    CODE
    issues.size.should eq(1)
  end

  it "flags a raise nested in a block inside the callback" do
    issues = raise_in_lib_callback_issues(<<-CODE)
      lib LibWatch
        fun each(cb : Int32 -> Void) : Void
      end

      LibWatch.each(->(row : Int32) {
        3.times { raise "boom" } # still unwinds through C
      })
    CODE
    issues.size.should eq(1)
  end

  it "flags every raise in the callback separately" do
    issues = raise_in_lib_callback_issues(<<-CODE)
      lib LibWatch
        fun each(cb : Int32 -> Void) : Void
      end

      LibWatch.each(->(row : Int32) {
        raise "a" if row < 0
        raise "b" if row > 9
      })
    CODE
    issues.size.should eq(2)
  end

  it "passes when the callback signals errors without raising" do
    raise_in_lib_callback_issues(<<-CODE).should be_empty
      lib LibWatch
        fun each(cb : Int32 -> Int32) : Void
      end

      LibWatch.each(->(row : Int32) {
        row < 0 ? 1 : 0
      })
    CODE
  end

  it "ignores raises in procs passed to non-lib receivers" do
    raise_in_lib_callback_issues(<<-CODE).should be_empty
      class Watch
        def self.each(&cb : Int32 -> Void); end
      end

      Watch.each(->(row : Int32) {
        raise "row is corrupt"
      })
    CODE
  end

  it "ignores raises in plain defs — only callbacks cross into C" do
    raise_in_lib_callback_issues(<<-CODE).should be_empty
      lib LibWatch
        fun each(cb : Int32 -> Void) : Void
      end

      def validate(row)
        raise "row is corrupt" # raised on the Crystal side — fine
      end
    CODE
  end

  it "ignores a proc stored in a variable and passed later" do
    # false negative by design: only proc literals passed directly as
    # arguments are tracked
    raise_in_lib_callback_issues(<<-CODE).should be_empty
      lib LibWatch
        fun each(cb : Int32 -> Void) : Void
      end

      cb = ->(row : Int32) { raise "row is corrupt" }
      LibWatch.each(cb)
    CODE
  end

  it "flags callbacks into stdlib-style Lib-prefixed shims too" do
    issues = raise_in_lib_callback_issues(<<-CODE)
      LibC.at_exit(->{
        raise "dying"
      })
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("LibC.at_exit")
  end
end
