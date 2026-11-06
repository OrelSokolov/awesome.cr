require "./spec_helper"

# Live smoke test: examples/awful/ carries the bad snippet of every
# guard, one file per guard, and the real runner must flag each guard
# exactly once. Keep examples/awful/ in sync when a guard is added.
describe "examples/awful" do
  it "fires every guard exactly once" do
    dir = File.expand_path("../examples/awful", __DIR__)
    report = Awesome::Runner.new(Awesome::Config.new).run([dir])

    fired = report.issues.map(&.guard).tally
    expected = Awesome::Guard.all.map { |g| {g.name, 1} }.to_h
    fired.should eq(expected)
  end
end
