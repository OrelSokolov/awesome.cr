require "./spec_helper"

def to_unsafe_escape_issues(code : String, config_yaml : String? = nil) : Array(Awesome::Issue)
  guard_issues(Awesome::Guards::ToUnsafeEscape, code, config_yaml)
end

describe Awesome::Guards::ToUnsafeEscape do
  it "flags a to_unsafe pointer stored in an ivar" do
    issues = to_unsafe_escape_issues(<<-CODE)
      class Decoder
        def initialize(@blob : Slice(UInt8))
          @raw = @blob.to_unsafe
        end
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(3)
    issues[0].message.should contain("@raw")
  end

  it "flags class vars and constants the same way" do
    issues = to_unsafe_escape_issues(<<-CODE)
      HEADER = "PK".to_unsafe

      class App
        def initialize(data : Slice(UInt8))
          @@raw = data.to_unsafe
        end
      end
    CODE
    issues.size.should eq(2)
  end

  it "flags an explicit return of a to_unsafe pointer" do
    issues = to_unsafe_escape_issues(<<-CODE)
      class Decoder
        def initialize(@blob : Slice(UInt8))
        end

        def raw_ptr
          return @blob.to_unsafe
        end
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(6)
    issues[0].message.should contain("return")
  end

  it "passes when the pointer is passed straight into a lib call" do
    to_unsafe_escape_issues(<<-CODE).should be_empty
      lib LibFoo
        fun draw(data : UInt8*, size : Int32) : Void
      end

      class Decoder
        def initialize(@blob : Slice(UInt8))
        end

        def draw
          LibFoo.draw(@blob.to_unsafe, @blob.size)
        end
      end
    CODE
  end

  it "passes when the owner is kept alive next to the pointer" do
    to_unsafe_escape_issues(<<-CODE).should be_empty
      class Decoder
        def initialize(@blob : Slice(UInt8))
          @raw = @blob.to_unsafe # pointer into the GC heap...
          @keep = @blob          # ...whose owner stays reachable
        end
      end
    CODE
  end

  it "ignores other method calls assigned to ivars" do
    to_unsafe_escape_issues(<<-CODE).should be_empty
      class Decoder
        def initialize(data : Slice(UInt8))
          @copy = data.dup
          @size = data.size
        end
      end
    CODE
  end

  it "ignores wrapping shapes (a false negative by design)" do
    to_unsafe_escape_issues(<<-CODE).should be_empty
      class Decoder
        def initialize(@blob : Slice(UInt8))
          @raw = @blob.to_unsafe.as(Int8*)
        end
      end
    CODE
  end
end
