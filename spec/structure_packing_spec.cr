require "./spec_helper"

describe Awesome::Guards::StructurePacking do
  it "passes a properly packed struct" do
    issues = pack_issues(<<-CODE)
      struct Pixel
        getter value : Int64
        getter red : Int32
        getter green : UInt8
        getter blue : UInt8
      end
    CODE
    issues.should be_empty
  end

  it "flags a struct that wastes bytes on padding" do
    issues = pack_issues(<<-CODE)
      struct Pixel
        getter red : UInt8
        getter value : Int64
        getter green : UInt8
        getter blue : UInt8
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain("24")
    issues[0].message.should contain("16")
  end

  it "suggests shrinking StaticArray fields" do
    issues = pack_issues(<<-CODE)
      struct Buffer
        getter tag : UInt8
        getter data : StaticArray(Int32, 100)
        getter flag : UInt8
      end
    CODE
    issues.size.should eq(1)
    # 1 + pad 3 + 400 + 1 = 405 rounded to 408 vs 400 + 1 + 1 = 402 → 404
    issues[0].message.should contain("408")
    issues[0].message.should contain("404")
  end

  it "handles plain @ivar declarations" do
    issues = pack_issues(<<-CODE)
      struct Plain
        @a : UInt8
        @b : Int64
        @c : UInt8
        def initialize(@a, @b, @c); end
      end
    CODE
    issues.size.should eq(1)
  end

  it "skips Packed structs" do
    pack_issues(<<-CODE).should be_empty
      @[Packed]
      struct Packed
        getter a : UInt8
        getter b : Int64
      end
    CODE
  end

  it "skips Alignment-annotated structs" do
    pack_issues(<<-CODE).should be_empty
      @[Alignment(16)]
      struct Aligned
        getter a : UInt8
        getter b : Int64
      end
    CODE
  end

  it "skips Extern structs unless check_extern is on" do
    code = <<-CODE
      @[Extern]
      struct Ext
        property a : UInt8 = 0
        property b : Int64 = 0
        property c : UInt8 = 0
      end
    CODE
    pack_issues(code).should be_empty
    pack_issues(code, "StructurePacking:\n  check_extern: true").size.should eq(1)
  end

  it "skips structs with unprovable field types (no false positives)" do
    pack_issues(<<-CODE).should be_empty
      struct HasCustom
        getter a : UInt8
        getter other : SomeCustomType
        getter b : Int64
      end
    CODE
  end

  it "skips untyped getter declarations" do
    pack_issues(<<-CODE).should be_empty
      struct NoAnn
        getter a
        getter b : Int64
        def initialize(@a : UInt8, @b : Int64); end
      end
    CODE
  end

  it "ignores classes and single-field structs" do
    pack_issues(<<-CODE).should be_empty
      class NotStruct
        getter a : UInt8
        getter b : Int64
      end
      struct Single
        getter a : UInt8
      end
    CODE
  end

  it "computes union field layout by widest member" do
    issues = pack_issues(<<-CODE)
      struct WithUnion
        getter a : UInt8
        getter val : Int32 | UInt16
        getter b : UInt8
      end
    CODE
    # union(Int32, UInt16) is {align 4, size 4}:
    # 1 + pad 3 + 4 + 1 = 12 vs 4 + 1 + 1 = 8
    issues.size.should eq(1)
    issues[0].message.should contain("12")
    issues[0].message.should contain("8")
  end

  it "checks structs nested in modules" do
    issues = pack_issues(<<-CODE)
      module Outer
        struct Nested
          getter a : UInt8
          getter b : Float64
          getter c : UInt8
        end
      end
    CODE
    issues.size.should eq(1)
  end
end
