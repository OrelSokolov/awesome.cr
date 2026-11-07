require "./spec_helper"

def unpinned_lib_callback_issues(code : String, config_yaml : String? = nil) : Array(Awesome::Issue)
  guard_issues(Awesome::Guards::UnpinnedLibCallback, code, config_yaml)
end

describe Awesome::Guards::UnpinnedLibCallback do
  it "flags a proc literal passed inline to a storing fun" do
    issues = unpinned_lib_callback_issues(<<-CODE)
      lib LibUi
        fun on_click(cb : Int32 -> Void) : Void
      end

      LibUi.on_click(->(button : Int32) {
        Counter.add(button)
      })
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(5)
    issues[0].message.should contain("LibUi.on_click")
    issues[0].message.should contain("GC")
  end

  it "flags set_/register_/subscribe_-style and *_handler names too" do
    issues = unpinned_lib_callback_issues(<<-CODE)
      lib LibBus
        fun set_logger(cb : Int32 -> Void) : Void
        fun register_listener(cb : Int32 -> Void) : Void
        fun subscribe_feed(cb : Int32 -> Void) : Void
        fun signal_error(cb : Int32 -> Void) : Void
      end

      LibBus.set_logger(->(level : Int32) { Log.write(level) })
      LibBus.register_listener(->(level : Int32) { Log.write(level) })
      LibBus.subscribe_feed(->(level : Int32) { Log.write(level) })
      LibBus.signal_error(->(code : Int32) { Log.write(code) })
    CODE
    issues.size.should eq(3)
  end

  it "flags an inline Box.box passed to a storing fun" do
    issues = unpinned_lib_callback_issues(<<-CODE)
      lib LibStore
        fun set_user_data(data : Void*) : Void
      end

      LibStore.set_user_data(Box.box(session))
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("Box")
  end

  it "ignores a proc kept in a constant and passed by name" do
    unpinned_lib_callback_issues(<<-CODE).should be_empty
      lib LibUi
        fun on_click(cb : Int32 -> Void) : Void
      end

      ON_CLICK = ->(button : Int32) { Counter.add(button) }
      LibUi.on_click(ON_CLICK)
    CODE
  end

  it "ignores fire-and-forget fun names" do
    # the closure is stack-reachable for the whole call there
    unpinned_lib_callback_issues(<<-CODE).should be_empty
      lib LibSort
        fun qsort(cb : Int32 -> Void) : Void
        fun each(cb : Int32 -> Void) : Void
      end

      LibSort.qsort(->(a : Int32) { 0 })
      LibSort.each(->(x : Int32) { 0 })
    CODE
  end

  it "ignores procs passed to non-lib receivers" do
    unpinned_lib_callback_issues(<<-CODE).should be_empty
      class Ui
        def self.on_click(&cb : Int32 -> Void); end
      end

      Ui.on_click(->(button : Int32) { Counter.add(button) })
    CODE
  end

  it "honours extra storing fun names from the config" do
    config = <<-YAML
      UnpinnedLibCallback:
        storage_funs: [run_with]
      YAML
    code = <<-CODE
      lib LibTask
        fun run_with(cb : Int32 -> Void) : Void
      end

      LibTask.run_with(->(a : Int32) { 0 })
    CODE
    unpinned_lib_callback_issues(code).should be_empty          # not tracked by default
    unpinned_lib_callback_issues(code, config).size.should eq(1) # opted in
  end

  it "honours ignore_funs — a storing-looking name that doesn't store" do
    config = <<-YAML
      UnpinnedLibCallback:
        ignore_funs: [on_init]
      YAML
    code = <<-CODE
      lib LibCore
        fun on_init(cb : Int32 -> Void) : Void # fires the callback now
      end

      LibCore.on_init(->(a : Int32) { 0 })
    CODE
    unpinned_lib_callback_issues(code).size.should eq(1)          # heuristic fires
    unpinned_lib_callback_issues(code, config).should be_empty    # suppressed
  end

  it "does not fire on callbacks stored in a variable and passed later" do
    # false negative by design: only literals at the call site are tracked
    unpinned_lib_callback_issues(<<-CODE).should be_empty
      lib LibUi
        fun on_click(cb : Int32 -> Void) : Void
      end

      cb = ->(button : Int32) { Counter.add(button) }
      LibUi.on_click(cb)
    CODE
  end
end
