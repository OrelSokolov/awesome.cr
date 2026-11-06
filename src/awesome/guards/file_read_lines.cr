# FileReadLines — slurping a file to walk its lines.
#
# Rust lore: `BufReader::lines` streams; `read_to_string` slurps.
# `File.read_lines(path)` in Crystal reads the whole file into memory,
# then allocates a String per line, all up front — for a big input that
# is peak memory proportional to the file size. `File.each_line(path)`
# yields line by line from a buffered read, so peak memory stays flat.
#
# The guard flags every `File.read_lines` call; if you genuinely need
# the whole Array (random access, re-iteration), ignore the finding.
class Awesome::Guards::FileReadLines < Awesome::Guard
  KIND = "memory"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for `File.read_lines(…)` calls. They slurp the whole file
    and allocate every line's String up front — peak memory proportional
    to file size. `File.each_line(…)` streams from a buffered read with
    flat memory use (Crystal's BufReader::lines). If you really need
    the whole Array, ignore the finding.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    File.each_line(path) do |line|
      process line
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    File.read_lines(path).each do |line|
      process line
    end
    # whole file + every String already in memory
  CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    def initialize(@source : Awesome::Source)
    end

    def visit(node : Crystal::Call)
      if node.name == "read_lines" && (obj = node.obj).is_a?(Crystal::Path) &&
         obj.names.size == 1 && obj.names.first == "File"
        @issues << Awesome::Issue.new(
          @source.path,
          "FileReadLines",
          "File.read_lines reads the whole file into memory before the first " \
          "line is used; File.each_line streams with flat memory use",
          node.location,
          @source.excerpt_at(node.location.try(&.line_number) || 0)
        )
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::FileReadLines
