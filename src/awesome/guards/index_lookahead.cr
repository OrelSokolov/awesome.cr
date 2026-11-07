# IndexLookahead — `xs.size.times { |i| … xs[i + 1] … }` runs one
# past the end on the last iteration.
#
# Neighbor access is the pattern (compare/swap with the next element),
# and the bug is always the same: the loop is bounded by `xs.size` —
# last `i` is `xs.size - 1` — while the body reads `xs[i + k]` with
# `k ≥ 1`, which is index `xs.size` at most one line before the raise.
#
# The provable shape: the bound is a bare `xs.size` (a `times` call or
# an exclusive `0...xs.size` range — an adjusted `xs.size - 1` end is
# the safe form and skipped), and the body indexes that same receiver
# with `i + k`. Any comparison mentioning the loop variable anywhere
# in the body suppresses the issue: the author is already guarding
# the boundary, and a false negative beats a false positive.
class Awesome::Guards::IndexLookahead < Awesome::Guard
  LEVEL    = "vibecoder" # crashes on first run, not a style nit
  SEVERITY = "bug"       # runtime-breaker: IndexError on the last iteration

  SHORT_DESCRIPTION = <<-TEXT
    Checks for lookahead indexing past the end of the loop's own
    collection: `xs.size.times { |i| … xs[i + 1] … }` (or
    `(0...xs.size).each`) — the last `i` is `xs.size - 1`, so `xs[i + 1]`
    is out of bounds. Guard the last iteration (`next if i + 1 ==
    xs.size`) or loop over `0...xs.size - 1`. Any comparison on the
    index in the body already counts as a guard and is skipped.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    items.each_with_index do |item, i|
      process items[i + 1] if i + 1 < items.size
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    items.size.times do |i|
      process items[i + 1]   # IndexError on the last iteration
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
         !compares_index?(block.body, index.name)
        LookaheadScan.new(self, recv, index.name).tap do |scan|
          block.body.accept(scan)
        end
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    private def loop_var(block : Crystal::Block) : Crystal::Var?
      return nil unless block.args.size == 1
      block.args.first.as?(Crystal::Var)
    end

    # The receiver whose bare `xs.size` bounds the loop, meaning the
    # block's last index into it is `xs.size - 1`: a `xs.size.times`
    # call or an exclusive `(… xs.size).each` range. Anything else —
    # plain `n.times`, an inclusive range, an adjusted `xs.size - 1`
    # end — can't prove the bound and returns nil.
    private def bounded_receiver(node : Crystal::Call) : String?
      case node.name
      when "times"
        return nil unless node.args.empty?
        size_receiver(node.obj)
      when "each"
        return nil unless node.args.empty?
        range = case obj = unparen(node.obj)
                when Crystal::RangeLiteral then obj
                else                            return nil
                end
        return nil unless range.exclusive?
        size_receiver(range.to)
      else nil
      end
    end

    # Strip a single-expression paren wrap: `(0...n).each` parses with
    # an Expressions node around the range.
    private def unparen(obj : Crystal::ASTNode?) : Crystal::ASTNode?
      if obj.is_a?(Crystal::Expressions) && obj.expressions.size == 1
        obj.expressions.first
      else
        obj
      end
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

    # Any comparison on the loop variable anywhere in the body — the
    # author is guarding the boundary; stay quiet (false negative,
    # never a false positive).
    private def compares_index?(body : Crystal::ASTNode, index : String) : Bool
      scan = CompareScan.new(index)
      body.accept(scan)
      scan.found?
    end

    # Finds `recv[i + k]` (k ≥ 1) inside one bounded loop body.
    private class LookaheadScan < Crystal::Visitor
      def initialize(@visitor : Visitor, @receiver : String, @index : String)
      end

      def visit(node : Crystal::Call)
        if node.name == "[]" && node.args.size == 1 &&
           (obj = node.obj) && obj.to_s == @receiver &&
           (offset = lookahead_offset(node.args.first))
          @visitor.add_issue(node, @receiver, @index, offset)
        end
        true
      end

      def visit(node : Crystal::ASTNode)
        true
      end

      # `i + k` with the bare loop variable and a literal k ≥ 1; nil
      # for bare `i`, `i - 1` or anything not provably past the end.
      private def lookahead_offset(arg : Crystal::ASTNode) : Int32?
        return nil unless arg.is_a?(Crystal::Call) && arg.name == "+" &&
                          arg.args.size == 1 && (obj = arg.obj).is_a?(Crystal::Var) &&
                          obj.name == @index
        case lit = arg.args.first
        when Crystal::NumberLiteral then lit.value.to_i?.try { |k| k >= 1 ? k : nil }
        else                             nil
        end
      end
    end

    # Finds a comparison call mentioning the loop variable.
    private class CompareScan < Crystal::Visitor
      COMPARISONS = {"<", "<=", ">", ">=", "==", "!="}

      def initialize(@index : String)
        @found = false
      end

      def found? : Bool
        @found
      end

      def visit(node : Crystal::Call)
        if COMPARISONS.includes?(node.name) && mentions_var?(node)
          @found = true
          return false
        end
        true
      end

      def visit(node : Crystal::ASTNode)
        true
      end

      private def mentions_var?(node : Crystal::ASTNode) : Bool
        scan = VarScan.new(@index)
        node.accept(scan)
        scan.found?
      end
    end

    # Finds a bare use of a named local variable in a subtree.
    private class VarScan < Crystal::Visitor
      getter? found = false

      def initialize(@index : String)
      end

      def visit(node : Crystal::Var)
        @found = true if node.name == @index
        true
      end

      def visit(node : Crystal::ASTNode)
        true
      end
    end

    # Reached by LookaheadScan: report one offending access site.
    def add_issue(node : Crystal::Call, recv : String, index : String, offset : Int32) : Nil
      Awesome::Issue.new(
        @source.path,
        "IndexLookahead",
        Awesome::I18n.t("guards.IndexLookahead.main",
          recv: recv,
          index: index,
          offset: offset),
        node.location,
        @source.excerpt_at(node.location.try(&.line_number) || 0)
      ).tap { |issue| @issues << issue }
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::IndexLookahead
