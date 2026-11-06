# TimesIndex — `xs.size.times { |i| … xs[i] … }` pays for index
# machinery nobody needs.
#
# The idiom re-derives every element through a bounds-checked `[]`
# and drags an index variable through the block, when `xs.each { |x|
# … }` hands over the element itself — no Integer object, no bounds
# check. The guard fires only when the block provably uses the index
# solely to index the very same receiver (`xs[i]` appears and `i` is
# the block argument); anything richer is left alone.
class Awesome::Guards::TimesIndex < Awesome::Guard
  KIND = "speed"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for `xs.size.times { |i| … xs[i] … }` — every access pays a
    bounds-checked index lookup. `xs.each { |x| }` yields the element
    directly. Fires only when the block's index is used to index the
    same collection and takes nothing else provable into account.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    items.each do |item|
      process item
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    items.size.times do |i|
      process items[i]   # bounds check + index bookkeeping per element
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
      if node.name == "times" && node.args.empty? &&
         (block = node.block) && (size = node.obj).is_a?(Crystal::Call) &&
         size.name == "size" && size.args.empty? && size.block.nil? &&
         (recv = receiver_name(size.obj)) &&
         block.args.size == 1 && (index = block.args.first).is_a?(Crystal::Var) &&
         indexes_receiver?(block.body, recv, index.name)
        @issues << Awesome::Issue.new(
          @source.path,
          "TimesIndex",
          "#{recv}.size.times { |#{index.name}| … } re-derives elements through " \
          "a bounds-checked index; #{recv}.each { |x| } yields them directly",
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

    # Name of a plain receiver: a local (Var), an instance variable, or
    # a bare identifier — the parser renders an undefined local as a
    # 0-arg Call, so `items` and an assigned `items` must both match.
    private def receiver_name(obj : Crystal::ASTNode?) : String?
      case obj
      when Crystal::Var, Crystal::InstanceVar then obj.to_s.lchop('@')
      when Crystal::Call
        obj.name if obj.args.empty? && obj.obj.nil? && obj.block.nil?
      else nil
      end
    end

    # True when the body contains `receiver[index]` for the exact
    # receiver/index pair. Absence is a false negative (fine); presence
    # proves the index exists only to re-fetch elements.
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

Awesome::Guard.registered << Awesome::Guards::TimesIndex
