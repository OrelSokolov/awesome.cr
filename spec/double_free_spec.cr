require "./spec_helper"

def double_free_issues(code : String, config_yaml : String? = nil) : Array(Awesome::Issue)
  guard_issues(Awesome::Guards::DoubleFree, code, config_yaml)
end

describe Awesome::Guards::DoubleFree do
  it "flags the same pointer freed twice with no reassignment" do
    issues = double_free_issues(<<-CODE)
      lib LibGeo
        fun free(ptr : Void*)
      end

      def close(ptr)
        LibGeo.free(ptr)
        cleanup
        LibGeo.free(ptr)
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(8)
    issues[0].message.should contain("LibGeo.free(ptr)")
    issues[0].message.should contain("line 6")
  end

  it "passes when the variable is reassigned between the frees" do
    double_free_issues(<<-CODE).should be_empty
      lib LibGeo
        fun malloc(size : Int32) : Void*
        fun realloc(ptr : Void*, size : Int32) : Void*
        fun free(ptr : Void*)
      end

      def cycle(ptr)
        LibGeo.free(ptr)
        ptr = LibGeo.malloc(64)
        LibGeo.free(ptr)
        ptr = LibGeo.realloc(ptr, 128)
        LibGeo.free(ptr)
      end
    CODE
  end

  it "does not pair frees from sibling if/else branches" do
    double_free_issues(<<-CODE).should be_empty
      def close(ptr, late)
        if late
          LibC.free(ptr)
        else
          LibC.free(ptr)
        end
      end
    CODE
  end

  it "does not flag when only the second free is conditional" do
    # false-negative by design: `free if cond` wraps the call in an If,
    # so only statement-level frees are paired
    double_free_issues(<<-CODE).should be_empty
      def close(ptr, again)
        LibC.free(ptr)
        LibC.free(ptr) if again
      end
    CODE
  end

  it "tracks instance variables too" do
    issues = double_free_issues(<<-CODE)
      class Buffer
        def close
          LibC.free(@ptr)
          LibC.free(@ptr)
        end
      end
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("@ptr")
  end

  it "ignores frees of different variables" do
    double_free_issues(<<-CODE).should be_empty
      def close(a, b)
        LibC.free(a)
        LibC.free(b)
      end
    CODE
  end

  it "ignores non-lib and non-deallocator calls" do
    double_free_issues(<<-CODE).should be_empty
      class Foo
        def self.free(x); end
      end

      def close(ptr)
        Foo.free(ptr)
        Foo.free(ptr)
        ptr.clear
        ptr.clear
      end
    CODE
  end

  it "ignores frees with zero or several arguments" do
    double_free_issues(<<-CODE).should be_empty
      lib LibGeo
        fun free_all : Void
        fun free_n(ptr : Void*, n : Int32) : Void
      end
      LibGeo.free_all
      LibGeo.free_all
      LibGeo.free_n(ptr, 2)
      LibGeo.free_n(ptr, 2)
    CODE
  end

  it "supports custom deallocator names via config" do
    code = <<-CODE
      lib MyFFI
        fun my_release(ptr : Void*)
      end

      def close(p)
        MyFFI.my_release(p)
        MyFFI.my_release(p)
      end
    CODE
    double_free_issues(code).should be_empty
    issues = double_free_issues(code, "DoubleFree:\n  deallocators: [my_release]")
    issues.size.should eq(1)
    issues[0].message.should contain("MyFFI.my_release(p)")
  end

  it "flags three frees as two issues on the second and third" do
    issues = double_free_issues(<<-CODE)
      def close(x)
        LibC.free(x)
        LibC.free(x)
        LibC.free(x)
      end
    CODE
    issues.size.should eq(2)
    issues[0].line.should eq(3)
    issues[1].line.should eq(4)
  end

  it "an assignment hidden inside a block between frees suppresses the issue" do
    double_free_issues(<<-CODE).should be_empty
      def close(ptr)
        LibC.free(ptr)
        1.times { ptr = LibC.malloc(8) }
        LibC.free(ptr)
      end
    CODE
  end

  it "flags a double free at top level" do
    issues = double_free_issues(<<-CODE)
      data = LibC.malloc(8)
      LibC.free(data)
      LibC.free(data)
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(3)
  end
end
