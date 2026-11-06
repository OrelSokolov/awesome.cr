require "./spec_helper"

# Single snippet runs as a one-file project; an Array(String) is a
# multi-file project (one Source per string).
def memory_issues(code : String | Array(String), config_yaml : String? = nil) : Array(Awesome::Issue)
  codes = code.is_a?(String) ? [code] : code
  guard_project_issues(Awesome::Guards::MemoryLeak, codes, config_yaml)
end

describe Awesome::Guards::MemoryLeak do
  it "flags an allocation with no matching free in the file" do
    issues = memory_issues(<<-CODE)
      lib LibGeo
        fun malloc(size : Int32) : Void*
        fun free(ptr : Void*)
      end

      class Polygon
        def initialize
          @points = LibGeo.malloc(64)
        end
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(8)
    issues[0].message.should contain("LibGeo.malloc")
    issues[0].message.should contain("initialize")
    issues[0].message.should contain("LibGeo.free")
  end

  it "passes when the allocation is paired with a free" do
    memory_issues(<<-CODE).should be_empty
      lib LibGeo
        fun malloc(size : Int32) : Void*
        fun free(ptr : Void*)
      end

      class Polygon
        def initialize
          @points = LibGeo.malloc(64)
        end

        def finalize
          LibGeo.free(@points)
        end
      end
    CODE
  end

  it "accepts a single free covering several allocations (base case)" do
    memory_issues(<<-CODE).should be_empty
      lib LibGeo
        fun malloc(size : Int32) : Void*
        fun free(ptr : Void*)
      end
      a = LibGeo.malloc(8)
      b = LibGeo.malloc(16)
      LibGeo.free(a)
    CODE
  end

  it "flags other default allocators too" do
    ["calloc", "realloc", "xmalloc", "strdup"].each do |allocator|
      issues = memory_issues("ptr = LibC.#{allocator}(16)")
      issues.size.should eq(1)
      issues[0].message.should contain("LibC.#{allocator}")
    end
  end

  it "tracks libs not declared in the file via the Lib prefix" do
    issues = memory_issues(<<-CODE)
      def make
        LibC.malloc(64)
      end
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("LibC.free")
  end

  it "ignores non-lib receivers" do
    memory_issues(<<-CODE).should be_empty
      class Foo
        def self.malloc(size : Int32)
          Slice(UInt8).new(size)
        end
      end

      buf = Foo.malloc(64)
    CODE
  end

  it "ignores calls to non-allocator funs" do
    memory_issues(<<-CODE).should be_empty
      lib LibGeo
        fun compute(x : Int32) : Int32
      end
      LibGeo.compute(1)
    CODE
  end

  it "does not mix libs: freeing one does not excuse another" do
    issues = memory_issues(<<-CODE)
      lib LibA
        fun malloc(size : Int32) : Void*
        fun free(ptr : Void*)
      end
      lib LibB
        fun xmalloc(size : Int32) : Void*
        fun xfree(ptr : Void*)
      end
      a = LibA.malloc(8)
      b = LibB.xmalloc(8)
      LibA.free(a)
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("LibB.xmalloc")
  end

  it "reports a leak even when malloc lives at top level" do
    issues = memory_issues("ptr = LibC.malloc(16)")
    issues.size.should eq(1)
    issues[0].message.should contain("top level")
  end

  it "accepts a free in another file (reopened class, cleanup module)" do
    issues = memory_issues([
      <<-CODE,
        class Polygon
          def initialize
            @points = LibC.malloc(64)
          end
        end
      CODE
      <<-CODE,
        class Polygon
          def finalize
            LibC.free(@points) # the pairing lives in another file
          end
        end
      CODE
    ])
    issues.should be_empty
  end

  it "flags an allocation no file in the project frees" do
    issues = memory_issues([
      "a = LibC.malloc(16)",
      "def helper; end",
    ])
    issues.size.should eq(1)
    issues[0].path.should eq("(test0)")
  end

  it "tracks a lib declared in one file and used in another" do
    issues = memory_issues([
      "lib Geo\n  fun malloc(size : Int32) : Void*\n  fun free(ptr : Void*)\nend",
      "ptr = Geo.malloc(8) # no Lib prefix — tracked via the declaration anyway",
    ])
    issues.size.should eq(1)
    issues[0].path.should eq("(test1)")

    issues = memory_issues([
      "lib Geo\n  fun malloc(size : Int32) : Void*\n  fun free(ptr : Void*)\nend",
      "ptr = Geo.malloc(8)",
      "Geo.free(ptr)",
    ])
    issues.should be_empty
  end

  it "supports custom allocator/deallocator names via config" do
    code = <<-CODE
      lib MyFFI
        fun my_alloc(size : Int32) : Void*
        fun my_release(ptr : Void*)
      end
      MyFFI.my_alloc(8)
    CODE
    memory_issues(code).should be_empty
    issues = memory_issues(code, "MemoryLeak:\n  allocators: [my_alloc]\n  deallocators: [my_release]")
    issues.size.should eq(1)
    issues[0].message.should contain("MyFFI.my_release")
  end

  it "passes when the free sits in a destructor further away in the file" do
    memory_issues(<<-CODE).should be_empty
      class Buffer
        def initialize
          @ptr = LibC.malloc(64)
        end

        def close
          LibC.free(@ptr)
        end
      end
    CODE
  end
end
