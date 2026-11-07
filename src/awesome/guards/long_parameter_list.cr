# LongParameterList — a method that takes a crowd.
#
# The method-level twin of GodClass: whether a parameter list is "too
# long" is not semantic, but the working-memory window isn't endless —
# past ~7 parameters a call site becomes unreadable and every
# parameter after that is usually part of a concept begging to be its
# own type. The guard states the count and the two honest fixes:
# bundle the parameters (an options/request struct) or split the
# method. Thresholds are configurable and the default is deliberately
# high — outliers first.
class Awesome::Guards::LongParameterList < Awesome::Guard
  KIND = "code"
  SHORT_DESCRIPTION = <<-TEXT
    Checks for methods taking more parameters than a call site can
    read (default 7) — stated as a fact, with two fixes: bundle the
    parameters into one concept (a request/options struct) or split
    the method. The default threshold points at outliers; lower it to
    5 for stricter checking.
  TEXT

  GOOD_EXAMPLE = <<-CODE
    class Mailer
      def send(message : Message) # one concept — the parameters travel together
      end
    end

    struct Message
      getter to : String
      getter subject : String
    end
  CODE

  BAD_EXAMPLE = <<-CODE
    class Mailer
      def send(to, from, subject, body, cc, bcc, reply_to, attachments)
        # 8 parameters — a Message struct wants to exist
      end
    end
  CODE

  MAX_PARAMS = 7

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new
    source.ast.try &.accept(visitor)

    max_params = config.int("max_params", MAX_PARAMS)

    visitor.facts.select { |fact| fact.params > max_params }.map do |fact|
      Awesome::Issue.new(
        source.path,
        "LongParameterList",
        Awesome::I18n.t("guards.LongParameterList.main",
          label: fact.label, count: fact.params, threshold: max_params),
        fact.location,
        source.excerpt_at(fact.location.try(&.line_number) || 0)
      )
    end
  end

  record Fact, label : String, params : Int32, location : Crystal::Location? do
    def line : Int32
      @location.try(&.line_number) || 0
    end
  end

  # Counts positional parameters per def. `*rest` counts as one; the
  # block argument doesn't count. The label carries the enclosing
  # type ("Mailer#send") when the def lives in one, plain name
  # otherwise. Nested types are tracked; top-level defs are label-only.
  private class Visitor < Crystal::Visitor
    getter facts = [] of Fact

    @nesting = [] of String

    def visit(node : Crystal::ClassDef | Crystal::ModuleDef)
      @nesting << node.name.to_s
      true
    end

    def end_visit(node : Crystal::ClassDef | Crystal::ModuleDef)
      @nesting.pop
    end

    def visit(node : Crystal::Def)
      label = @nesting.empty? ? node.name : "#{@nesting.join("::")}##{node.name}"
      facts << Fact.new(label, node.args.size, node.location)
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::LongParameterList
