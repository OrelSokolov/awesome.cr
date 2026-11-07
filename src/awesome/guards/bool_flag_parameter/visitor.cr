# Visitor for BoolFlagParameter — see guards/bool_flag_parameter.cr.
# One visitor per source, appending into the shared Evidence: def
# params and call-site literals land in the same tables whatever
# file they come from.
class Awesome::Guards::BoolFlagParameter::Visitor < Crystal::Visitor
  def initialize(@path : String, @evidence : Evidence)
  end

  def visit(node : Crystal::Def)
    @evidence.add_def(node.name)
    return true if node.receiver || node.name == "initialize" || operator?(node.name)

    node.args.each_with_index do |arg, index|
      next unless bool_restricted?(arg)
      @evidence.add_bool_param(BoolParam.new(@path, node.name, arg.name, index, node.location))
    end
    true
  end

  def visit(node : Crystal::Call)
    node.args.each_with_index do |arg, index|
      if arg.is_a?(Crystal::BoolLiteral)
        @evidence.add_positional(node.name, index, arg.value)
      end
    end
    node.named_args.try &.each do |named|
      if value = named.value.as?(Crystal::BoolLiteral)
        @evidence.add_named(node.name, named.name, value.value)
      end
    end
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end

  private def bool_restricted?(arg : Crystal::Arg) : Bool
    restriction = arg.restriction
    restriction.is_a?(Crystal::Path) && restriction.to_s == "Bool"
  end

  private def operator?(name : String) : Bool
    !name.matches?(/\A[a-z_]\w*[?!]?\z/)
  end
end
