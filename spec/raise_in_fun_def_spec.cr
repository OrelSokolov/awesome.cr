require "./spec_helper"

def raise_in_fun_def_issues(code : String, config_yaml : String? = nil) : Array(Awesome::Issue)
  guard_issues(Awesome::Guards::RaiseInFunDef, code, config_yaml)
end

describe Awesome::Guards::RaiseInFunDef do
  it "flags a raise inside a fun def" do
    issues = raise_in_fun_def_issues(<<-CODE)
      fun vib_push(h : Int64) : Int64
        raise "bad handle"
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(2)
    issues[0].message.should contain("fun")
  end

  it "flags reraise and raises nested in blocks" do
    issues = raise_in_fun_def_issues(<<-CODE)
      fun vib_each(h : Int64) : Int64
        3.times { raise "row is corrupt" }
        reraise
      end
    CODE
    issues.size.should eq(2)
  end

  it "passes when the fun catches the exception and returns an error code" do
    raise_in_fun_def_issues(<<-CODE).should be_empty
      fun vib_push(h : Int64) : Int64
        State.push(h)
        0
      rescue
        -1
      end
    CODE
  end

  it "passes when the raise is inside a begin/rescue in the fun body" do
    raise_in_fun_def_issues(<<-CODE).should be_empty
      fun vib_push(h : Int64) : Int64
        begin
          raise "bad handle"
        rescue
          return -1
        end
      end
    CODE
  end

  it "ignores raises in plain defs — only funs are C entry points" do
    raise_in_fun_def_issues(<<-CODE).should be_empty
      def validate(h)
        raise "bad handle" # raised on the Crystal side — fine
      end
    CODE
  end

  it "ignores fun declarations inside a lib (no body)" do
    raise_in_fun_def_issues(<<-CODE).should be_empty
      lib LibWatch
        fun each(cb : Int32 -> Void) : Void
      end
    CODE
  end
end
