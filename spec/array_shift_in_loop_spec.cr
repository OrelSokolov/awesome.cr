require "./spec_helper"

describe Awesome::Guards::ArrayShiftInLoop do
  it "flags shift on an array in a while loop" do
    issues = guard_issues(Awesome::Guards::ArrayShiftInLoop, <<-CODE)
      queue = [1, 2, 3]
      while item = queue.shift?
        process item
      end
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(2)
    issues[0].message.should contain("Deque")
  end

  it "flags unshift inside a block iterator" do
    issues = guard_issues(Awesome::Guards::ArrayShiftInLoop, <<-CODE)
      queue = [1, 2, 3]
      10.times do
        queue.unshift(next_item)
      end
    CODE
    issues.size.should eq(1)
    issues[0].message.should contain("unshift")
  end

  it "does not flag shift outside loops" do
    guard_issues(Awesome::Guards::ArrayShiftInLoop, <<-CODE).should be_empty
      queue = [1, 2, 3]
      first = queue.shift
    CODE
  end

  it "does not flag bare Kernel#shift-style calls without a receiver" do
    guard_issues(Awesome::Guards::ArrayShiftInLoop, <<-CODE).should be_empty
      while x = shift
        process x
      end
    CODE
  end

  it "does not flag other calls in loops" do
    guard_issues(Awesome::Guards::ArrayShiftInLoop, <<-CODE).should be_empty
      queue = [1, 2, 3]
      queue.each do |item|
        process item
      end
    CODE
  end
end
