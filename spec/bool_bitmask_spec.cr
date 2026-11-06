require "./spec_helper"

describe Awesome::Guards::BoolBitmask do
  it "passes a struct with few Bool fields" do
    guard_issues(Awesome::Guards::BoolBitmask, <<-CODE).should be_empty
      struct Entry
        getter readable : Bool
        getter writable : Bool
      end
    CODE
  end

  it "flags a struct with four Bool fields" do
    issues = guard_issues(Awesome::Guards::BoolBitmask, <<-CODE)
      struct Entry
        getter readable : Bool
        getter writable : Bool
        getter executable : Bool
        getter sticky : Bool
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain("4")
    issues[0].message.should contain("into 1")
    issues[0].message.should contain("@[Flags]")
  end

  it "counts @ivar declarations too" do
    issues = guard_issues(Awesome::Guards::BoolBitmask, <<-CODE)
      struct Plain
        @a : Bool
        @b : Bool
        @c : Bool
        @d : Bool
        @e : Bool
        def initialize(@a, @b, @c, @d, @e); end
      end
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("5")
  end

  it "honors a custom min_bools" do
    code = <<-CODE
      struct Entry
        getter readable : Bool
        getter writable : Bool
      end
    CODE
    guard_issues(Awesome::Guards::BoolBitmask, code).should be_empty
    yaml = "BoolBitmask:\n  min_bools: 2"
    guard_issues(Awesome::Guards::BoolBitmask, code, yaml).size.should eq(1)
  end

  it "skips Extern structs" do
    guard_issues(Awesome::Guards::BoolBitmask, <<-CODE).should be_empty
      @[Extern]
      struct Ext
        property a : Bool = false
        property b : Bool = false
        property c : Bool = false
        property d : Bool = false
      end
    CODE
  end

  it "ignores classes and non-Bool fields" do
    guard_issues(Awesome::Guards::BoolBitmask, <<-CODE).should be_empty
      class NotStruct
        getter a : Bool
        getter b : Bool
        getter c : Bool
        getter d : Bool
      end
      struct Mixed
        getter a : Bool
        getter b : Bool
        getter c : Bool
        getter name : String
      end
    CODE
  end
end
