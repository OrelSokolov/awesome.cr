require "./spec_helper"

def unchecked_lib_pointer_issues(code : String, config_yaml : String? = nil) : Array(Awesome::Issue)
  guard_issues(Awesome::Guards::UncheckedLibPointer, code, config_yaml)
end

describe Awesome::Guards::UncheckedLibPointer do
  it "flags a chained deref right on the lib call" do
    issues = unchecked_lib_pointer_issues(<<-CODE)
      lib LibGeo
        fun find(id : Int32) : Float64*
      end

      def fetch(id)
        LibGeo.find(id).value
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(6)
    issues[0].message.should contain("LibGeo.find(id).value")
  end

  it "flags a stored deref with no check in between" do
    issues = unchecked_lib_pointer_issues(<<-CODE)
      lib LibGeo
        fun find(id : Int32) : Float64*
      end

      def fetch(id)
        point = LibGeo.find(id)
        point.value
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(7)
    issues[0].message.should contain("line 6")
  end

  it "passes when the deref is guarded by `if var = ...` right at the source" do
    unchecked_lib_pointer_issues(<<-CODE).should be_empty
      lib LibGeo
        fun find(id : Int32) : Float64*
      end

      def fetch(id)
        if point = LibGeo.find(id)
          point.value
        end
      end
    CODE
  end

  it "passes when an `if var` appears between assignment and deref" do
    unchecked_lib_pointer_issues(<<-CODE).should be_empty
      lib LibGeo
        fun find(id : Int32) : Float64*
      end

      def fetch(id)
        point = LibGeo.find(id)
        if point
          point.value
        end
      end
    CODE
  end

  it "passes when the check is `unless var.nil?`" do
    unchecked_lib_pointer_issues(<<-CODE).should be_empty
      lib LibGeo
        fun find(id : Int32) : Float64*
      end

      def fetch(id)
        point = LibGeo.find(id)
        unless point.nil?
          point.value
        end
      end
    CODE
  end

  it "passes when the variable is reassigned to a non-lib value" do
    unchecked_lib_pointer_issues(<<-CODE).should be_empty
      lib LibGeo
        fun find(id : Int32) : Float64*
      end

      def fetch(id, fallback)
        point = LibGeo.find(id)
        point = fallback
        point.value
      end
    CODE
  end

  it "keeps tracking when the reassignment is from the lib again" do
    issues = unchecked_lib_pointer_issues(<<-CODE)
      lib LibGeo
        fun find(id : Int32) : Float64*
        fun origin : Float64*
      end

      def fetch(id)
        point = LibGeo.origin
        point = LibGeo.find(id)
        point.value
      end
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("LibGeo.find(id)")
  end

  it "skips declared funs that do not return a pointer" do
    unchecked_lib_pointer_issues(<<-CODE).should be_empty
      lib LibGeo
        fun plain(id : Int32) : Int32
      end

      def fetch(id)
        x = LibGeo.plain(id)
        LibGeo.plain(id)
      end
    CODE
  end

  it "flags Lib-prefixed shims bound elsewhere (LibC)" do
    issues = unchecked_lib_pointer_issues(<<-CODE)
      def home
        LibC.getenv("HOME").value
      end
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("LibC.getenv")
  end

  it "ignores derefs of variables that never came from a lib call" do
    unchecked_lib_pointer_issues(<<-CODE).should be_empty
      def fetch(point)
        point.value
      end
    CODE
  end

  it "ignores non-lib calls chained into .value" do
    unchecked_lib_pointer_issues(<<-CODE).should be_empty
      def fetch(id)
        repo.find(id).value
      end
    CODE
  end

  it "flags instance variables tracked across statements" do
    issues = unchecked_lib_pointer_issues(<<-CODE)
      lib LibGeo
        fun find(id : Int32) : Float64*
      end

      class Fetcher
        def load(id)
          @point = LibGeo.find(id)
          @point.value
        end
      end
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("@point")
  end

  it "does not mix scopes: a same-named local inside a def is separate" do
    unchecked_lib_pointer_issues(<<-CODE).should be_empty
      lib LibGeo
        fun find(id : Int32) : Float64*
      end

      point = LibGeo.find(1)

      def use(point)
        point.value
      end
    CODE
  end
end
