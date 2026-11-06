# ArrayShiftInLoop — Array is the wrong queue.
#
# Rust lore: `Vec::remove(0)` in a loop is O(n²); use a `VecDeque` with
# O(1) pops at both ends. In Crystal `Array#shift`/`#unshift` likewise
# move the whole buffer (memmove per call), while `Deque` is
# ring-buffered with O(1) `shift`/`#unshift`.
#
# Advisory: any receiver works for `shift`, not just Array (Hash#shift
# is O(1)), so the message asks you to check the receiver's type. Loop
# detection matches while/until plus the common block iterators; a
# missed iterator only means a false negative.
class Awesome::Guards::ArrayShiftInLoop < Awesome::Guard
  KIND = "speed"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for `shift`/`unshift` calls on arrays inside loops.
    Array#shift and #unshift are O(n) — every call moves the whole
    buffer, turning a queue loop into O(n²). Use a Deque (Crystal's
    VecDeque) for queue access: O(1) at both ends. Advisory: if the
    receiver is not an Array (e.g. Hash#shift, which is O(1)), ignore
    the finding.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    queue = Deque{first, second}
    while item = queue.shift?   # O(1)
      process item
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    queue = [first, second]
    while item = queue.shift?   # O(n) memmove per call
      process item
    end
  CODE

  # Call-with-block methods that run their block zero or more times.
  ITERATORS = {"times", "each", "each_with_index", "map", "loop",
               "upto", "downto", "step"}

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.issues
  end

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    def initialize(@source : Awesome::Source)
    end

    @loop_depth = 0

    def visit(node : Crystal::While | Crystal::Until)
      @loop_depth += 1
      true
    end

    def end_visit(node : Crystal::While | Crystal::Until)
      @loop_depth -= 1
    end

    def visit(node : Crystal::Call)
      @loop_depth += 1 if loop_call?(node)
      if @loop_depth > 0 && node.obj && {"shift", "shift?", "unshift"}.includes?(node.name)
        add_issue(node)
      end
      true
    end

    def end_visit(node : Crystal::Call)
      @loop_depth -= 1 if loop_call?(node)
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    private def loop_call?(node : Crystal::Call) : Bool
      !node.block.nil? && ITERATORS.includes?(node.name)
    end

    private def add_issue(node : Crystal::Call)
      @issues << Awesome::Issue.new(
        @source.path,
        "ArrayShiftInLoop",
        "##{node.name} inside a loop is O(n) per call on an Array " \
        "(O(n²) for the loop); use a Deque for queue access",
        node.location,
        @source.excerpt_at(node.location.try(&.line_number) || 0)
      )
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::ArrayShiftInLoop
