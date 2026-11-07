# SelfSizeIndex — `xs[xs.size]` indexes one past the last element.
#
# The classic off-by-one: for every stdlib container the last valid
# index is `size - 1`, so `xs[xs.size]` raises the moment it runs
# (Array/String: IndexError; Hash: KeyError). No receiver makes the
# pattern legal, which is what makes it provable syntactically.
#
# Two forms are caught: the direct `xs[xs.size]`, and the alias
# `n = xs.size … xs[n]` — the alias is tracked within one statement
# block, DoubleFree-style, and any reassignment of `n` in between
# clears it. `[]?` is skipped: `xs[xs.size]?` is the deliberate
# nil-on-miss form, not a crash.
class Awesome::Guards::SelfSizeIndex < Awesome::Guard
  LEVEL    = "vibecoder" # crashes on first run, not a style nit
  SEVERITY = "bug"       # runtime-breaker: guaranteed IndexError/KeyError

  SHORT_DESCRIPTION = <<-TEXT
    Checks for indexing a collection by its own size: `xs[xs.size]` (or
    `n = xs.size … xs[n]`) — valid indices run 0..size - 1, so the
    access is always out of bounds. The last element is `xs.last` /
    `xs[size - 1]`. The nilable `xs[xs.size]?` form is left alone.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    last = items[items.size - 1]
    first_empty = items[items.size]? # deliberate nil-on-miss
  CODE

  BAD_EXAMPLE = <<-CODE
    last = items[items.size] # one past the end — IndexError

    n = rows.size
    tail = rows[n]           # same bug through an alias
  CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source)
    source.ast.try &.accept(visitor)
    visitor.analyze
    visitor.issues
  end

  private class Visitor < Crystal::Visitor
    getter issues = [] of Awesome::Issue

    # Statement blocks are collected during traversal and re-scanned
    # after it, once every alias in the block is known.
    @blocks = [] of Array(Crystal::ASTNode)

    def initialize(@source : Awesome::Source)
    end

    # The direct form fires right during traversal — no context needed.
    def visit(node : Crystal::Call)
      if (recv = indexed_receiver(node)) &&
         (arg = node.args.first?) && size_receiver(arg) == recv
        @issues << issue(node, "#{recv}.size", nil)
      end
      true
    end

    def visit(node : Crystal::Expressions)
      @blocks << node.expressions
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    # After traversal: pair `n = xs.size` with later `xs[n]` inside
    # each statement block, honoring reassignments in between.
    def analyze : Nil
      @blocks.each do |exprs|
        aliases = {} of String => {recv: String, line: Int32}
        exprs.each do |expr|
          check_aliased(expr, aliases)
          refresh_aliases(expr, aliases)
        end
      end
    end

    # `xs[n]` where `n` still aliases this receiver's size — the
    # access may sit anywhere in the statement (`tail = xs[n]`).
    private def check_aliased(expr : Crystal::ASTNode, aliases) : Nil
      aliases.each do |name, alias_|
        scan = AliasScan.new(self, name, alias_[:recv], alias_[:line])
        expr.accept(scan)
      end
    end

    # A fresh `n = xs.size` records the alias; any other assignment to
    # a tracked name (even nested in the statement) clears it — a
    # reassigned index is no longer provably the size.
    private def refresh_aliases(expr : Crystal::ASTNode, aliases) : Nil
      aliases.reject! { |name, _| assigns?(expr, name) }
      if expr.is_a?(Crystal::Assign) &&
         (target = expr.target).is_a?(Crystal::Var | Crystal::InstanceVar) &&
         (recv = size_receiver(expr.value))
        aliases[target.to_s] = {recv: recv,
                                line: expr.location.try(&.line_number) || 0}
      end
    end

    # Receiver of a bounds-checked `xs[...]` (not `[]?`), as written —
    # a local (Var), an instance variable, or a bare identifier (the
    # parser renders an undefined local as a 0-arg Call).
    private def indexed_receiver(node : Crystal::Call) : String?
      return nil unless node.name == "[]" && node.args.size == 1
      plain_name(node.obj)
    end

    # Receiver of a `xs.size` call — a zero-arg, blockless `size` on a
    # plainly named receiver; nil for anything else.
    private def size_receiver(node : Crystal::ASTNode) : String?
      return nil unless node.is_a?(Crystal::Call) &&
                        node.name == "size" && node.args.empty? && node.block.nil?
      plain_name(node.obj)
    end

    private def plain_name(obj : Crystal::ASTNode?) : String?
      case obj
      when Crystal::Var, Crystal::InstanceVar then obj.to_s
      when Crystal::Call
        obj.name if obj.args.empty? && obj.obj.nil? && obj.block.nil?
      else nil
      end
    end

    # Any assignment (`=`, op-assign, multi-assign) to a name anywhere
    # in a subtree — the alias's value is no longer provable.
    private def assigns?(expr : Crystal::ASTNode, name : String) : Bool
      scanner = AssignScanner.new(name)
      expr.accept(scanner)
      scanner.found?
    end

    # Reached by AliasScan: report one `xs[n]` access site.
    def add_issue(node : Crystal::Call, what : String, def_line : Int32) : Nil
      @issues << issue(node, what, def_line)
    end

    # Finds `recv[name]` for one still-tracked size alias, anywhere in
    # a statement subtree.
    private class AliasScan < Crystal::Visitor
      def initialize(@visitor : Visitor, @name : String, @recv : String,
                     @line : Int32)
      end

      def visit(node : Crystal::Call)
        if node.name == "[]" && node.args.size == 1 &&
           (arg = node.args.first).is_a?(Crystal::Var | Crystal::InstanceVar) &&
           arg.to_s == @name && plain_receiver(node) == @recv
          @visitor.add_issue(node, @name, @line)
        end
        true
      end

      def visit(node : Crystal::ASTNode)
        true
      end

      private def plain_receiver(node : Crystal::Call) : String?
        case obj = node.obj
        when Crystal::Var, Crystal::InstanceVar then obj.to_s
        when Crystal::Call
          obj.name if obj.args.empty? && obj.obj.nil? && obj.block.nil?
        else nil
        end
      end
    end

    private def issue(node : Crystal::Call, what : String, def_line : Int32?) : Awesome::Issue
      origin = def_line ? " (set at line #{def_line})" : ""
      Awesome::Issue.new(
        @source.path,
        "SelfSizeIndex",
        Awesome::I18n.t("guards.SelfSizeIndex.main", what: what, origin: origin),
        node.location,
        @source.excerpt_at(node.location.try(&.line_number) || 0)
      )
    end

    # Flags any assignment to a given local/ivar name in a subtree.
    private class AssignScanner < Crystal::Visitor
      getter? found = false

      def initialize(@name : String)
      end

      def visit(node : Crystal::Assign)
        check(node.target)
        true
      end

      def visit(node : Crystal::OpAssign)
        check(node.target)
        true
      end

      def visit(node : Crystal::MultiAssign)
        node.targets.each { |t| check(t) }
        true
      end

      def visit(node : Crystal::ASTNode)
        true
      end

      private def check(target : Crystal::ASTNode)
        if target.is_a?(Crystal::Var | Crystal::InstanceVar) &&
           target.to_s == @name
          @found = true
        end
      end
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::SelfSizeIndex
