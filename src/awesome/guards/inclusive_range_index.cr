# InclusiveRangeIndex — `(0..xs.size).each { |i| xs[i] }` reaches
# index `xs.size` on the last pass.
#
# The inclusive `..` range runs its last iteration with
# `i == xs.size`, and `xs[i]` raises IndexError right there. The
# provable shape: the range (or `upto`) ends at a bare `xs.size`, and
# the block indexes that same receiver with the bare loop variable —
# `xs[i - 1]` or any offset is left alone, as are the safe exclusive
# forms (`...`, `times`, `0...xs.size`).
class Awesome::Guards::InclusiveRangeIndex < Awesome::Guard
  LEVEL    = "vibecoder" # crashes on first run, not a style nit
  SEVERITY = "bug"       # runtime-breaker: IndexError on the last iteration

  SHORT_DESCRIPTION = <<-TEXT
    Checks for `(0..xs.size).each { |i| … xs[i] … }` and
    `1.upto(xs.size) { |i| … xs[i] … }` — the inclusive bound yields
    `i == xs.size` on the last iteration, and `xs[i]` raises
    IndexError. Use the exclusive `0...xs.size` or `xs.size.times`.
    Fires only when the block indexes that same receiver with the bare
    loop variable.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    (0...items.size).each do |i|
      process items[i]
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    (0..items.size).each do |i|
      process items[i]   # i == items.size on the last pass
    end
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
      if (block = node.block) && (index = loop_var(block)) &&
         (recv = bounded_receiver(node)) &&
         indexes_receiver?(block.body, recv, index.name)
        @issues << Awesome::Issue.new(
          @source.path,
          "InclusiveRangeIndex",
          "the loop's last `#{index.name}` is `#{recv}.size`, where " \
          "`#{recv}[#{index.name}]` raises IndexError — use the exclusive " \
          "range `0...#{recv}.size` or `#{recv}.size.times`",
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

    # The receiver whose size bounds the loop, when the loop is an
    # inclusive `… xs.size` iteration over it:
    # `(a..xs.size).each` or `k.upto(xs.size)`. Exclusive ranges and
    # adjusted ends (`xs.size - 1`) are the safe forms — nil.
    private def bounded_receiver(node : Crystal::Call) : String?
      case node.name
      when "each"
        return nil unless node.args.empty? && (block = node.block) && block.args.size == 1
        range = case obj = unparen(node.obj)
                when Crystal::RangeLiteral then obj
                else                            return nil
                end
        return nil if range.exclusive?
        size_receiver(range.to)
      when "upto"
        return nil unless node.args.size == 1 && node.obj.is_a?(Crystal::NumberLiteral)
        size_receiver(node.args.first)
      else nil
      end
    end

    # Strip a single-expression paren wrap: `(0..n).each` parses with
    # an Expressions node around the range.
    private def unparen(obj : Crystal::ASTNode?) : Crystal::ASTNode?
      if obj.is_a?(Crystal::Expressions) && obj.expressions.size == 1
        obj.expressions.first
      else
        obj
      end
    end

    private def loop_var(block : Crystal::Block) : Crystal::Var?
      return nil unless block.args.size == 1
      block.args.first.as?(Crystal::Var)
    end

    # Receiver of a bare `xs.size` call; nil for anything else
    # (`xs.size - 1` included — an adjusted end is the safe form).
    private def size_receiver(node : Crystal::ASTNode?) : String?
      return nil unless node.is_a?(Crystal::Call) &&
                        node.name == "size" && node.args.empty? && node.block.nil?
      case obj = node.obj
      when Crystal::Var, Crystal::InstanceVar then obj.to_s
      when Crystal::Call
        obj.name if obj.args.empty? && obj.obj.nil? && obj.block.nil?
      else nil
      end
    end

    # True when the body contains `receiver[i]` with the exact bare
    # loop variable — anything offset (`i - 1`) can't be judged here.
    private def indexes_receiver?(body : Crystal::ASTNode, receiver : String, index : String) : Bool
      scan = IndexScan.new(receiver, index)
      body.accept(scan)
      scan.found?
    end
  end

  private class IndexScan < Crystal::Visitor
    def initialize(@receiver : String, @index : String)
      @found = false
    end

    def found? : Bool
      @found
    end

    def visit(node : Crystal::Call)
      if node.name == "[]" && node.args.size == 1 &&
         (obj = node.obj) && obj.to_s == @receiver &&
         (arg = node.args.first).is_a?(Crystal::Var) && arg.name == @index
        @found = true
      end
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::InclusiveRangeIndex
