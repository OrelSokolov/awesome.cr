require "./spec_helper"

describe Awesome::Guards::HardcodedDependency do
  it "flags a concrete construction when the owner already works with the abstraction" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-CODE])
      class Store
        def warm; end
      end

      class MemoryStore < Store
        def warm; end
      end

      class RedisStore < Store
        def warm; end
      end

      class Reporter
        def initialize(@store : Store)
        end

        def rebuild
          cache = MemoryStore.new
          cache.warm
        end
      end
      CODE
    issues.size.should eq(1)
    issues[0].line.should be > 0
    issues[0].message.should contain("Reporter constructs MemoryStore.new")
    issues[0].message.should contain("Reporter#rebuild")
    issues[0].message.should contain("2 implementations")
  end

  it "treats a parameter restriction as using the abstraction" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-CODE])
      class Store
        def warm; end
      end

      class MemoryStore < Store
        def warm; end
      end

      class RedisStore < Store
        def warm; end
      end

      class Reporter
        def rebuild(store : Store)
          cache = MemoryStore.new
          cache.warm
        end
      end
      CODE
    issues.size.should eq(1)
  end

  it "flags the module half of a seam too (include)" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-CODE])
      module Backend
        def call; end
      end

      class FastBackend
        include Backend

        def call; end
      end

      class SlowBackend
        include Backend

        def call; end
      end

      class Gate
        def initialize(@backend : Backend)
        end

        def open
          FastBackend.new.call
        end
      end
      CODE
    issues.size.should eq(1)
    issues[0].message.should contain("Gate constructs FastBackend.new")
    issues[0].message.should contain("Backend")
  end

  it "stays silent when the owner never declared the abstraction" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-CODE])
      class Store
        def warm; end
      end

      class MemoryStore < Store
        def warm; end
      end

      class RedisStore < Store
        def warm; end
      end

      class Job
        def run
          RedisStore.new # no contradiction — maybe it genuinely needs Redis
        end
      end
      CODE
    issues.should be_empty
  end

  it "stays silent without a seam: no abstraction, single implementation" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-CODE])
      class Shape
        def area; 0; end
      end

      class Parser
        def build_shape
          Shape.new # the parser's result — constructing it is the job
        end
      end
      CODE
    issues.should be_empty
  end

  it "stays silent about external types and value objects" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-CODE])
      class Store
        def warm; end
      end

      class MemoryStore < Store
        def warm; end
      end

      class RedisStore < Store
        def warm; end
      end

      struct Vec
        def initialize(@x : Int32, @y : Int32); end
      end

      class Worker
        def initialize(@store : Store)
        end

        def tick
          Vec.new(1, 2)               # struct — data plumbing
          HTTP::Client.new("x")       # external — no evidence available
        end
      end
      CODE
    issues.should be_empty
  end

  it "keeps the classic skips: initialize, factories, exceptions, nested helpers" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-CODE])
      class Store
        def warm; end
      end

      class MemoryStore < Store
        def warm; end
      end

      class RedisStore < Store
        def warm; end
      end

      class Reporter
        def initialize(@store : Store)
          @extra = MemoryStore.new # initialize — wiring, allowed
        end

        def self.build
          MemoryStore.new          # factory class-method — its job
        end

        def pick : Store
          MemoryStore.new          # return-type factory — choosing is its job
        end

        def fail
          raise StoreError.new("boom")
        end

        private class Helper
          def initialize(@raw : String); end
        end

        def parse(raw)
          Helper.new(raw)          # own nested helper
        end
      end

      class StoreError < Exception
      end
      CODE
    issues.should be_empty
  end

  it "anchors issues to the file the construction is in" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-STORES, <<-REPORTER])
      class Store
        def warm; end
      end

      class MemoryStore < Store
        def warm; end
      end

      class RedisStore < Store
        def warm; end
      end
      STORES
      class Reporter
        def initialize(@store : Store)
        end

        def rebuild
          MemoryStore.new
        end
      end
      REPORTER
    issues.size.should eq(1)
    issues[0].path.should eq("(test1)")
  end

  it "flags a construction of one sibling while another sibling is annotated" do
    issues = guard_project_issues(Awesome::Guards::HardcodedDependency, [<<-CODE])
      class Store
        def warm; end
      end

      class MemoryStore < Store
        def warm; end
      end

      class RedisStore < Store
        def warm; end
      end

      class Reporter
        def initialize(@backup : MemoryStore)
        end

        def rebuild
          RedisStore.new # the family is declared, the choice is welded in
        end
      end
      CODE
    issues.size.should eq(1)
  end

  it "respects the allowed whitelist by path and namespace" do
    code = [<<-CODE]
      class Store
        def warm; end
      end

      class MemoryStore < Store
        def warm; end
      end

      class RedisStore < Store
        def warm; end
      end

      class Reporter
        def initialize(@store : Store)
        end

        def rebuild
          MemoryStore.new
        end
      end
      CODE
    yaml = <<-YAML
      HardcodedDependency:
        allowed: [MemoryStore]
      YAML
    guard_project_issues(Awesome::Guards::HardcodedDependency, code, yaml).should be_empty
  end
end
