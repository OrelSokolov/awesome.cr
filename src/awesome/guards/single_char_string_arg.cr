# SingleCharStringArg — a one-character String literal where a Char
# overload exists.
#
# `String#includes?`, `#split`, `#starts_with?`, `#ends_with?`,
# `#replace`, `#sub` and `#gsub` all have Char overloads next to their
# String ones. `s.split(",")` slices on a String separator — length
# checks, byte-wise compares; `s.split(',')` compares one character
# code. Free win, zero semantic change, which is exactly why the guard
# only fires on provable single-character literals.
class Awesome::Guards::SingleCharStringArg < Awesome::Guard
  KIND = "speed"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for single-character String literal arguments to split,
    includes?, starts_with?, ends_with?, replace, sub and gsub. Each of
    them has a Char overload that compares character codes instead of
    Strings — s.split(",") → s.split(','). Multi-character strings and
    non-literal arguments are left alone.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    parts = path.split('/')
    broken = text.gsub('a', 'b')
  CODE

  BAD_EXAMPLE = <<-CODE
    parts = path.split("/")
    broken = text.gsub("a", "b")
    # String separator: length checks + string compare
    # where a character compare would do
  CODE

  # method => exact arg count whose every arg must be a 1-char String
  # literal for the Char overloads to apply.
  METHODS = {
    "split" => 1, "includes?" => 1, "starts_with?" => 1, "ends_with?" => 1,
    "replace" => 2, "sub" => 2, "gsub" => 2,
  }

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
      if (arity = METHODS[node.name]?) && !node.obj.nil? && node.block.nil? &&
         node.args.size == arity && node.args.all?(&.is_a?(Crystal::StringLiteral)) &&
         node.args.all? { |a| single_char?(a.as(Crystal::StringLiteral)) }
        char_args = node.args.map { |a| a.as(Crystal::StringLiteral).value[0].inspect }.join(", ")
        @issues << Awesome::Issue.new(
          @source.path,
          "SingleCharStringArg",
          "#{node.name} with single-character String literals compares whole " \
          "Strings; the Char overload #{node.name}(#{char_args}) compares " \
          "character codes directly",
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

    private def single_char?(literal : Crystal::StringLiteral) : Bool
      literal.value.size == 1
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::SingleCharStringArg
