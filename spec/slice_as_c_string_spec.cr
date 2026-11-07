require "./spec_helper"

def slice_as_c_string_issues(code : String, config_yaml : String? = nil) : Array(Awesome::Issue)
  guard_issues(Awesome::Guards::SliceAsCString, code, config_yaml)
end

describe Awesome::Guards::SliceAsCString do
  it "flags to_unsafe passed to a UInt8* param with no length argument" do
    issues = slice_as_c_string_issues(<<-CODE)
      lib LibCfg
        fun read(name : UInt8*) : Int32
      end

      LibCfg.read(buf.to_unsafe)
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(5)
    issues[0].message.should contain("LibCfg.read")
    issues[0].message.should contain("NUL")
  end

  it "flags Int8*/Char* params the same way" do
    issues = slice_as_c_string_issues(<<-CODE)
      lib LibCfg
        fun load(tag : Char*) : Int32
      end

      LibCfg.load(sym.to_unsafe)
    CODE
    issues.size.should eq(1)
  end

  it "passes when a length argument travels with the pointer" do
    slice_as_c_string_issues(<<-CODE).should be_empty
      lib LibCfg
        fun read_n(data : UInt8*, len : Int32) : Int32
      end

      LibCfg.read_n(buf.to_unsafe, buf.size)
      LibCfg.read_n(buf.to_unsafe, len) # a bare length-named var counts too
    CODE
  end

  it "passes when the to_unsafe is not on a string-ish parameter" do
    slice_as_c_string_issues(<<-CODE).should be_empty
      lib LibGfx
        fun draw(points : Float64*) : Void
      end

      LibGfx.draw(pts.to_unsafe) # Float64* is not read as a C string
    CODE
  end

  it "passes for a string literal receiver (NUL-terminated)" do
    slice_as_c_string_issues(<<-CODE).should be_empty
      lib LibCfg
        fun read(name : UInt8*) : Int32
      end

      LibCfg.read("default.cfg".to_unsafe)
    CODE
  end

  it "ignores calls into libs not declared in the file" do
    # the signature is unknown — a false negative by design
    slice_as_c_string_issues(<<-CODE).should be_empty
      LibC.puts(buf.to_unsafe)
    CODE
  end

  it "honours extra length names from the config" do
    config = <<-YAML
      SliceAsCString:
        length_names: [num_items]
      YAML
    code = <<-CODE
      lib LibCfg
        fun read(name : UInt8*) : Int32
      end

      LibCfg.read(buf.to_unsafe, buf.num_items)
    CODE
    slice_as_c_string_issues(code).size.should eq(1) # num_items not known by default
    slice_as_c_string_issues(code, config).should be_empty
  end
end
