require "./spec_helper"

describe Awesome::Guards::NilableStructField do
  it "passes a struct without nilable fields" do
    guard_issues(Awesome::Guards::NilableStructField, <<-CODE).should be_empty
      struct Session
        getter id : Int64
        getter closed : Bool
      end
    CODE
  end

  it "flags a nilable Int64 field" do
    issues = guard_issues(Awesome::Guards::NilableStructField, <<-CODE)
      struct Session
        getter id : Int64?
        getter closed : Bool
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(2)
    issues[0].message.should contain("16")
    issues[0].message.should contain("8")
    issues[0].message.should contain("id")
  end

  it "reports the size of a small nilable payload" do
    issues = guard_issues(Awesome::Guards::NilableStructField, <<-CODE)
      struct Cell
        getter flags : UInt8?
      end
    CODE
    # {Int32 tag, UInt8 payload} padded to 4-alignment = 8 bytes
    issues.size.should eq(1)
    issues[0].message.should contain("8")
    issues[0].message.should contain("1")
  end

  it "handles explicit Nil union syntax" do
    issues = guard_issues(Awesome::Guards::NilableStructField, <<-CODE)
      struct Session
        getter id : Int32 | Nil
      end
    CODE
    issues.size.should eq(1)
  end

  it "skips unions without Nil" do
    guard_issues(Awesome::Guards::NilableStructField, <<-CODE).should be_empty
      struct Cell
        getter val : Int32 | UInt16
      end
    CODE
  end

  it "skips nilable fields with unprovable payload types" do
    guard_issues(Awesome::Guards::NilableStructField, <<-CODE).should be_empty
      struct HasCustom
        getter other : SomeCustomType?
      end
    CODE
  end

  it "skips Extern structs" do
    guard_issues(Awesome::Guards::NilableStructField, <<-CODE).should be_empty
      @[Extern]
      struct Ext
        getter a : Int64?
      end
    CODE
  end

  it "ignores classes and plain @ivar declarations" do
    issues = guard_issues(Awesome::Guards::NilableStructField, <<-CODE)
      class NotStruct
        getter id : Int64?
      end
      struct Plain
        @id : Int64?
        def initialize(@id); end
      end
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("id")
  end
end
