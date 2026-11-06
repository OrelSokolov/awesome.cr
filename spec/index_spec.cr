require "./spec_helper"

describe Awesome::Index do
  it "indexes qualified names, superclasses, abstractness and def names" do
    index = Awesome::Index.new([Awesome::Source.new("(t1)", <<-CODE)])
      module App
        abstract class Base
          def helpful; end

          abstract def must
        end

        class Inner < Base
          def must; end
        end
      end

      class Top < App::Base; end

      struct Point; end

      module Util
        def self.answer; end
      end
      CODE

    base = index.find("App::Base").not_nil!
    base.abstract?.should be_true
    base.superclass.should be_nil
    base.def_names.should eq(["helpful", "must"])
    base.last_segment.should eq("Base")
    base.path.should eq("(t1)")
    base.line.should be > 0

    inner = index.find("App::Inner").not_nil!
    inner.superclass.should eq("Base")
    inner.abstract?.should be_false
    inner.def_names.should eq(["must"])

    top = index.find("Top").not_nil!
    top.superclass.should eq("App::Base")

    point = index.find("Point").not_nil!
    point.superclass.should be_nil

    util = index.find("Util").not_nil!
    util.def_names.should eq(["answer"])
  end

  it "indexes each source under its own path" do
    index = Awesome::Index.new([
      Awesome::Source.new("(a)", "class A; end"),
      Awesome::Source.new("(b)", "class B < A; end"),
    ])
    index.find("A").not_nil!.path.should eq("(a)")
    index.find("B").not_nil!.path.should eq("(b)")
  end

  it "resolves an exact qualified name first" do
    index = Awesome::Index.new([
      Awesome::Source.new("(a)", <<-CODE),
        class Base; end

        module Other
          class Base; end
        end
        CODE
      Awesome::Source.new("(b)", "class Child < Other::Base; end"),
    ])
    index.resolve("Other::Base").not_nil!.qualified_name.should eq("Other::Base")
  end

  it "falls back to a unique last-segment candidate" do
    index = Awesome::Index.new([
      Awesome::Source.new("(a)", "module App\n  class Base; end\nend"),
      Awesome::Source.new("(b)", "class Child < Base; end"),
    ])
    index.resolve("Base").not_nil!.qualified_name.should eq("App::Base")
  end

  it "returns nil for ambiguous candidates" do
    index = Awesome::Index.new([
      Awesome::Source.new("(a)", "module App\n  class Base; end\nend"),
      Awesome::Source.new("(b)", "module Other\n  class Base; end\nend"),
      Awesome::Source.new("(c)", "class Child < Base; end"), # written path matches neither qualified name
    ])
    index.by_last_segment("Base").size.should eq(2)
    index.resolve("Base").should be_nil
  end

  it "returns nil for external (unindexed) types" do
    index = Awesome::Index.new([Awesome::Source.new("(a)", "class Handler < Kemal::Base; end")])
    index.resolve("Kemal::Base").should be_nil
  end

  it "strips generics and leading :: from superclass paths" do
    index = Awesome::Index.new([Awesome::Source.new("(a)", <<-CODE)])
      class Base(T); end

      class Kid < Base(Int32); end

      class Root; end

      class Orphan < ::Root; end
      CODE
    index.find("Kid").not_nil!.superclass.should eq("Base")
    index.find("Orphan").not_nil!.superclass.should eq("Root")
    index.resolve("Root").should_not be_nil
  end

  it "lists direct subclasses via the resolution rules" do
    index = Awesome::Index.new([
      Awesome::Source.new("(a)", "module App\n  class Base; end\nend"),
      Awesome::Source.new("(b)", "class ExternalKid < HTTP::Handler; end"),
      Awesome::Source.new("(c)", <<-CODE),
        class KidA < Base; end

        class KidB < App::Base; end
        CODE
    ])
    base = index.find("App::Base").not_nil!
    subclasses = index.subclasses_of(base).map(&.qualified_name).sort
    subclasses.should eq(["KidA", "KidB"])
  end
end
