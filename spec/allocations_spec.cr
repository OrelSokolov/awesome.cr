require "./spec_helper"
require "file_utils"

# Single snippet runs as a one-file project; an Array(String) is a
# multi-file project (one Source per string). Returns per-file status
# arrays (0-based: statuses[0][2] is line 3 of the first file).
def allocation_statuses(code : String | Array(String), scope : String = "project") : Array(Array(Awesome::Allocations::Status))
  codes = code.is_a?(String) ? [code] : code
  sources = codes.map_with_index { |c, i| Awesome::Source.new("(test#{i})", c) }
  Awesome::Allocations.analyze(sources, scope).map(&.statuses)
end

describe Awesome::Allocations do
  it "reddens direct allocation constructs and keeps plain lines green" do
    statuses = allocation_statuses(<<-CODE)[0]
      xs = [1, 2, 3]
      s = "a\#{b}"
      f = Foo.new
      ys = xs.map { |x| x }
      p = LibC.malloc(8)
      t = "plain"
      n = 1
      m = {1, 2}
      r = (1..2)
    CODE
    statuses[0].should eq(Awesome::Allocations::Status::Red)   # Array literal
    statuses[1].should eq(Awesome::Allocations::Status::Red)   # interpolation
    statuses[2].should eq(Awesome::Allocations::Status::Red)   # .new
    statuses[3].should eq(Awesome::Allocations::Status::Red)   # .map
    statuses[4].should eq(Awesome::Allocations::Status::Red)   # C allocator
    statuses[5].should eq(Awesome::Allocations::Status::Green) # String literal is static
    statuses[6].should eq(Awesome::Allocations::Status::Green) # a number
    statuses[7].should eq(Awesome::Allocations::Status::Green) # tuple is stack
    statuses[8].should eq(Awesome::Allocations::Status::Green) # range is a struct
  end

  it "treats io-less to_s as an allocation, to_s(io) as a call" do
    statuses = allocation_statuses(<<-CODE)[0]
      a = x.to_s
      x.to_s(io)
    CODE
    statuses[0].should eq(Awesome::Allocations::Status::Red)
    statuses[1].should eq(Awesome::Allocations::Status::Gray) # unresolved overload
  end

  it "grays out calls the scope cannot resolve" do
    statuses = allocation_statuses(<<-CODE)[0]
      puts "hi"
      helper(1)
      y = 2
      y.nil?
    CODE
    statuses[0].should eq(Awesome::Allocations::Status::Gray)
    statuses[1].should eq(Awesome::Allocations::Status::Gray)
    statuses[2].should eq(Awesome::Allocations::Status::Green) # plain assignment
    statuses[3].should eq(Awesome::Allocations::Status::Green) # pure builtin on a local
  end

  it "reddens the def line of an allocating method, keeping clean body lines green" do
    statuses = allocation_statuses(<<-CODE)[0]
      def make
        x = 1
        [1, 2]
      end

      def wrap
        make
      end

      wrap
    CODE
    statuses[0].should eq(Awesome::Allocations::Status::Red)   # def make: body allocates
    statuses[1].should eq(Awesome::Allocations::Status::Green) # clean line inside a red def
    statuses[2].should eq(Awesome::Allocations::Status::Red)
    statuses[5].should eq(Awesome::Allocations::Status::Red)   # def wrap: calls an allocating method
    statuses[6].should eq(Awesome::Allocations::Status::Red)   # the call itself
    statuses[9].should eq(Awesome::Allocations::Status::Red)   # top-level call reddens too
  end

  it "keeps provably clean methods green" do
    statuses = allocation_statuses(<<-CODE)[0]
      def clean(x)
        x
      end

      clean(1)
    CODE
    statuses.all?(&.==(Awesome::Allocations::Status::Green)).should be_true
  end

  it "grays a def whose body calls unknown code" do
    statuses = allocation_statuses(<<-CODE)[0]
      def unclear
        helper(1)
      end
    CODE
    statuses[0].should eq(Awesome::Allocations::Status::Gray)
    statuses[1].should eq(Awesome::Allocations::Status::Gray)
  end

  it "converges on clean recursion without false positives" do
    statuses = allocation_statuses(<<-CODE)[0]
      def ping(x)
        pong(x)
      end

      def pong(x)
        ping(x)
      end

      ping(1)
    CODE
    statuses.all?(&.==(Awesome::Allocations::Status::Green)).should be_true
  end

  it "reddens a whole call cycle when one member allocates" do
    statuses = allocation_statuses(<<-CODE)[0]
      def a
        b
      end

      def b
        [1]
      end

      a
    CODE
    {0, 1, 4, 5, 8}.each do |i| # def a, call, def b, literal, top-level call
      statuses[i].should eq(Awesome::Allocations::Status::Red), "line #{i + 1}"
    end
  end

  it "merges overloads conservatively: one allocating def reddens every call" do
    statuses = allocation_statuses(<<-CODE)[0]
      def make
        [1]
      end

      def make(x)
        x
      end

      make
      make(1)
    CODE
    statuses[8].should eq(Awesome::Allocations::Status::Red)
    statuses[9].should eq(Awesome::Allocations::Status::Red)
  end

  it "resolves calls across files in project scope but not in file scope" do
    codes = ["def make\n  [1]\nend\n", "make\n"]

    project = allocation_statuses(codes, "project")
    project[0][0].should eq(Awesome::Allocations::Status::Red)
    project[1][0].should eq(Awesome::Allocations::Status::Red)

    file = allocation_statuses(codes, "file")
    file[0][0].should eq(Awesome::Allocations::Status::Red) # own file still knows
    file[1][0].should eq(Awesome::Allocations::Status::Gray) # make lives in another file
  end

  it "marks every line of an unparsable file gray" do
    source = Awesome::Source.new("(test)", "def broken(\n")
    Awesome::Allocations.analyze([source])[0].statuses
      .all?(&.==(Awesome::Allocations::Status::Gray)).should be_true
  end
end

describe Awesome::CLI do
  it "prints the allocations report in both scopes and rejects bad scopes" do
    dir = File.join(Dir.tempdir, "awesome_alloc_#{Random.new.hex(6)}")
    Dir.mkdir_p(dir)
    File.write(File.join(dir, "bad.cr"), "xs = [1, 2, 3]\n")

    Awesome::CLI.run(["allocations", dir]).should eq(0)
    Awesome::CLI.run(["allocations", "--scope", "file", dir]).should eq(0)
    Awesome::CLI.run(["allocations", "--scope", "bogus", dir]).should eq(2)
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
