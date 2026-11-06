# SelectCompareZero — a filtered Array built just to be compared with
# zero.
#
# `xs.select { |x| x > 1 }.size == 0` materializes the whole filtered
# Array to count it, then throws it away for a boolean. `xs.none? { |
# x| x > 1 }` answers the same question by short-circuiting on the
# first match — no allocation, no full pass. `.size > 0` is `any?`,
# `.empty?` on a select is `none?`.
class Awesome::Guards::SelectCompareZero < Awesome::Guard
  KIND = "speed"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for `xs.select { … }.size == 0` (and `.size > 0`,
    `.size >= 1`, `.empty?`). The select allocates the filtered Array
    just to compare its length with zero; `xs.none? { … }` (or `any?`)
    answers without the Array and stops at the first match.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    return if items.none? { |item| item.invalid? }
    proceed if items.any? { |item| item.urgent? }
  CODE

  BAD_EXAMPLE = <<-CODE
    return if items.select { |item| item.invalid? }.size == 0
    proceed if items.select { |item| item.urgent? }.size > 0
    #        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ filtered Array
    #        allocated, counted, discarded
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
      case node.name
      when "==", ">", ">="
        if node.args.size == 1 && (arg = node.args.first).is_a?(Crystal::NumberLiteral) &&
           (size = node.obj).is_a?(Crystal::Call) && size.name == "size" &&
           size.args.empty? && select_with_block?(size.obj)
          replacement = replacement_for(node.name, arg.to_s)
          add_issue(node, replacement) if replacement
        end
      when "empty?"
        if node.args.empty? && node.block.nil? && select_with_block?(node.obj)
          add_issue(node, "none? { … }")
        end
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    private def select_with_block?(node : Crystal::ASTNode?) : Bool
      node.is_a?(Crystal::Call) && node.name == "select" && !node.block.nil?
    end

    private def replacement_for(op : String, literal : String) : String?
      case {op, literal}
      when {"==", "0"} then "none? { … }"
      when {">", "0"}  then "any? { … }"
      when {">=", "1"} then "any? { … }"
      else                  nil
      end
    end

    private def add_issue(node : Crystal::Call, replacement : String)
      @issues << Awesome::Issue.new(
        @source.path,
        "SelectCompareZero",
        "select { … }.#{node.name}#{node.args.first? ? " " + node.args.first.to_s : ""} " \
        "builds the filtered Array just to compare with zero; " \
        "#{replacement} answers without it",
        node.location,
        @source.excerpt_at(node.location.try(&.line_number) || 0)
      )
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::SelectCompareZero
