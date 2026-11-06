# A Crystal source file: path, code and its parsed AST.
#
# Uses the compiler's own parser (`Crystal::Parser`, shipped with every
# Crystal install via `compiler/crystal/syntax/*`), so guards see the
# exact AST `crystal build` sees — 1:1, no reimplementation.
class Awesome::Source
  getter path : String
  getter code : String

  def initialize(@path : String, code : String? = nil)
    @code = code || begin
      File.read(@path)
    rescue
      ""
    end
  end

  # Parses the source; returns nil (and prints a warning to stderr) on
  # syntax errors — a broken file is a compiler problem, not a guard one.
  def ast : Crystal::ASTNode?
    @ast ||= begin
      parser = Crystal::Parser.new(@code)
      parser.filename = @path
      parser.parse
    rescue ex : Crystal::SyntaxException
      STDERR << "awesome: skipping " << @path << ": " << ex.message << '\n'
      nil
    end
  end

  def code_lines : Array(String)
    @code_lines ||= @code.split('\n')
  end

  def excerpt_at(line : Int32) : String?
    code_lines[line - 1]?
  end

  @ast : Crystal::ASTNode? = nil
  @code_lines : Array(String)? = nil
end
