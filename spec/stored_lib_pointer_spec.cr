require "./spec_helper"

def stored_lib_pointer_issues(code : String, config_yaml : String? = nil) : Array(Awesome::Issue)
  guard_issues(Awesome::Guards::StoredLibPointer, code, config_yaml)
end

describe Awesome::Guards::StoredLibPointer do
  it "flags a lib fun result stored in an ivar" do
    issues = stored_lib_pointer_issues(<<-CODE)
      lib LibEngine
        fun create : Void*
      end

      class Context
        def initialize
          @ctx = LibEngine.create
        end
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(7)
    issues[0].message.should contain("@ctx")
    issues[0].message.should contain("close")
  end

  it "flags class vars and constants the same way" do
    issues = stored_lib_pointer_issues(<<-CODE)
      lib LibEngine
        fun create : Void*
      end

      CTX = LibEngine.create
    CODE
    issues.size.should eq(1)
  end

  it "passes when the class manages the lifetime explicitly" do
    stored_lib_pointer_issues(<<-CODE).should be_empty
      lib LibEngine
        fun create : Void*
        fun destroy(ctx : Void*) : Void
      end

      class Context
        def initialize
          @ctx = LibEngine.create
        end

        def close
          LibEngine.destroy(@ctx)
        end
      end
    CODE
  end

  it "skips allocator funs — MemoryLeak owns that concern" do
    stored_lib_pointer_issues(<<-CODE).should be_empty
      lib LibGeo
        fun malloc(size : Int32) : Void*
      end

      class Polygon
        def initialize
          @points = LibGeo.malloc(64)
        end
      end
    CODE
  end

  it "skips calls on non-lib receivers" do
    stored_lib_pointer_issues(<<-CODE).should be_empty
      class Engine
        def self.create
          Pointer(Void).null
        end
      end

      class Context
        def initialize
          @ctx = Engine.create
        end
      end
    CODE
  end

  it "honours extra allocator names from the config" do
    config = <<-YAML
      StoredLibPointer:
        allocators: [malloc, create]
      YAML
    code = <<-CODE
      lib LibEngine
        fun create : Void*
      end

      CTX = LibEngine.create
    CODE
    stored_lib_pointer_issues(code).size.should eq(1) # create tracked by default
    stored_lib_pointer_issues(code, config).should be_empty
  end
end
