require "./spec_helper"

# JunkFile runs per file, so every case is a single snippet through
# guard_issues (see spec_helper).
describe Awesome::Guards::JunkFile do
  it "flags a second class in the same file" do
    issues = guard_issues(Awesome::Guards::JunkFile, <<-CODE)
      class User
        def initialize(@name : String)
        end
      end

      class Order
        def initialize(@user : User)
        end
      end
      CODE
    issues.size.should eq(1)
    issues[0].line.should be > 0
    issues[0].message.should contain("2 classes in one file")
    issues[0].message.should contain("User, Order")
  end

  it "allows one class per file" do
    guard_issues(Awesome::Guards::JunkFile, "class User\n  def initialize(@name : String)\n  end\nend\n").should be_empty
  end

  it "merges a class reopened in the same file" do
    issues = guard_issues(Awesome::Guards::JunkFile, "class User\nend\n\nclass User\n  def name; end\nend\n")
    issues.should be_empty
  end

  it "counts classes nested in modules toward the file's class count" do
    issues = guard_issues(Awesome::Guards::JunkFile, <<-CODE)
      module Shop
        class Cart
        end

        class Order
        end
      end
      CODE
    issues.size.should eq(1)
    issues[0].message.should contain("2 classes in one file")
    issues[0].message.should contain("Cart, Order")
  end

  it "flags a class nesting two classes, allows one" do
    ok = guard_issues(Awesome::Guards::JunkFile, <<-CODE)
      class Parser
        class Result
        end
      end
      CODE
    ok.should be_empty

    issues = guard_issues(Awesome::Guards::JunkFile, <<-CODE)
      class Parser
        class Result
        end

        class Error
        end
      end
      CODE
    issues.size.should eq(1)
    issues[0].message.should contain("class Parser nests 2 classes")
    issues[0].message.should contain("Result, Error")
  end

  it "flags a module nesting two modules, allows one" do
    ok = guard_issues(Awesome::Guards::JunkFile, <<-CODE)
      module Shop
        module Catalog
        end
      end
      CODE
    ok.should be_empty

    issues = guard_issues(Awesome::Guards::JunkFile, <<-CODE)
      module Shop
        module Catalog
        end

        module Billing
        end
      end
      CODE
    issues.size.should eq(1)
    issues[0].message.should contain("module Shop nests 2 modules")
    issues[0].message.should contain("Catalog, Billing")
  end

  it "allows a class chain one level deep at every level" do
    guard_issues(Awesome::Guards::JunkFile, <<-CODE).should be_empty
      class Outer
        class Inner
          class Core
          end
        end
      end
    CODE
  end

  it "skips structs — they are data, not classes" do
    guard_issues(Awesome::Guards::JunkFile, <<-CODE).should be_empty
      struct Point
        property x : Int32
        property y : Int32
      end

      struct Size
        property w : Int32
        property h : Int32
      end
    CODE
  end
end
