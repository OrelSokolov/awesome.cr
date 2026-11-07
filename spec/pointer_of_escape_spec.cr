require "./spec_helper"

def pointer_of_escape_issues(code : String, config_yaml : String? = nil) : Array(Awesome::Issue)
  guard_issues(Awesome::Guards::PointerOfEscape, code, config_yaml)
end

describe Awesome::Guards::PointerOfEscape do
  it "flags pointerof passed to a storing fun" do
    issues = pointer_of_escape_issues(<<-CODE)
      lib LibStats
        fun register_counter(addr : Int32*) : Void
      end

      LibStats.register_counter(pointerof(@count))
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(5)
    issues[0].message.should contain("LibStats.register_counter")
    issues[0].message.should contain("dangling")
  end

  it "flags set_/on_ names and pointerof stored in a field" do
    issues = pointer_of_escape_issues(<<-CODE)
      lib LibUi
        fun on_tick(addr : Int32*) : Void
        fun set_state(addr : Int32*) : Void
      end

      LibUi.on_tick(pointerof(ticks))
      LibUi.set_state(pointerof(state))
      STATE = pointerof(counter)
    CODE
    issues.size.should eq(3)
  end

  it "passes for fire-and-forget funs" do
    # the address only needs to live for the duration of the call
    pointer_of_escape_issues(<<-CODE).should be_empty
      lib LibMem
        fun fill(dst : Int32*, value : Int32) : Void
      end

      LibMem.fill(pointerof(slot), 7)
    CODE
  end

  it "passes when C copies the value instead of the address" do
    pointer_of_escape_issues(<<-CODE).should be_empty
      lib LibStats
        fun register_counter(value : Int32) : Void
      end

      LibStats.register_counter(@count)
    CODE
  end

  it "ignores pointerof on non-lib receivers" do
    pointer_of_escape_issues(<<-CODE).should be_empty
      class Stats
        def self.register_counter(x : Int32); end
      end

      Stats.register_counter(pointerof(@count))
    CODE
  end

  it "honours ignore_funs — a storing-looking name that doesn't store" do
    config = <<-YAML
      PointerOfEscape:
        ignore_funs: [register_my_thread]
      YAML
    code = <<-CODE
      lib LibBoehm
      end

      # Boehm copies the struct — the address never escapes the call
      LibBoehm.register_my_thread(pointerof(stack_base))
    CODE
    pointer_of_escape_issues(code).size.should eq(1) # heuristic fires
    pointer_of_escape_issues(code, config).should be_empty
  end

  it "honours extra storing fun names from the config" do
    config = <<-YAML
      PointerOfEscape:
        storage_funs: [observe]
      YAML
    code = <<-CODE
      lib LibWatch
        fun observe(addr : Int32*) : Void
      end

      LibWatch.observe(pointerof(counter))
    CODE
    pointer_of_escape_issues(code).should be_empty          # not tracked by default
    pointer_of_escape_issues(code, config).size.should eq(1) # opted in
  end
end
