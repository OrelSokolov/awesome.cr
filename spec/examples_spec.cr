require "./spec_helper"

# Live smoke test: examples/awful/ carries the bad snippets of every
# guard, one file per guard (AGENTS.md: a file may hold several
# examples of its guard). The real runner must fire every guard at
# least once, and each file must fire only its own guard — no
# cross-firing — with one exception: JunkFile fires on any awful file
# that is a multi-type junk pile, because most bad snippets need
# several types to misbehave (an inheritance chain needs three
# classes, etc). Runs at the top level so psycho guards fire too.
# Keep examples/awful/ in sync when a guard is added.
describe "examples/awful" do
  it "fires every guard, and only from its own file" do
    dir = File.expand_path("../examples/awful", __DIR__)
    report = Awesome::Runner.new(Awesome::Config.new, level: "psycho").run([dir])

    fired = report.issues.map(&.guard).uniq.sort
    expected = Awesome::Guard.all.map(&.name).sort
    fired.should eq(expected)

    # JunkFile must fire from its own file at least once…
    report.issues.any? do |issue|
      issue.guard == "JunkFile" && File.basename(issue.path, ".cr") == "junk_file"
    end.should be_true

    report.issues.each do |issue|
      # …but is allowed to fire from other awful files too: they are
      # deliberately multi-type junk piles, which is exactly what the
      # guard reports.
      next if issue.guard == "JunkFile"
      own = File.basename(issue.path, ".cr").split('_').map(&.capitalize).join
      issue.guard.should eq(own)
    end
  end
end
