# Result of a run: all issues plus how many files were inspected.
class Awesome::Report
  getter inspected : Int32
  getter issues : Array(Awesome::Issue)

  def initialize(@inspected : Int32)
    @issues = [] of Awesome::Issue
  end

  def add(issues : Array(Awesome::Issue))
    @issues.concat(issues)
  end

  def awesome? : Bool
    @issues.empty?
  end

  def sort!
    @issues.sort_by! { |i| {i.path, i.line, i.column} }
  end
end
