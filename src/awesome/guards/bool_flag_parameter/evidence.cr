# Evidence for BoolFlagParameter — see guards/bool_flag_parameter.cr.
# Cross-file evidence: Bool-restricted parameters of named defs,
# def-name counts (for the ambiguity skip), and literal Bool
# arguments at call sites — positional keyed by index, named by
# parameter name, both keyed by method name.
class Awesome::Guards::BoolFlagParameter::Evidence
  getter bool_params = [] of BoolParam
  @def_counts = Hash(String, Int32).new(0)
  @positional = {} of String => Array({Int32, Bool})
  @named = {} of String => Array({String, Bool})

  def defs_named(method_name : String) : Int32
    @def_counts[method_name]
  end

  def literals_for(method_name : String, index : Int32, param_name : String) : Set(Bool)
    seen = Set(Bool).new
    @positional[method_name]?.try &.each { |(i, v)| seen << v if i == index }
    @named[method_name]?.try &.each { |(n, v)| seen << v if n == param_name }
    seen
  end

  def add_def(method_name : String) : Nil
    @def_counts[method_name] += 1
  end

  def add_bool_param(param : BoolParam) : Nil
    @bool_params << param
  end

  def add_positional(method_name : String, index : Int32, value : Bool) : Nil
    (@positional[method_name] ||= [] of {Int32, Bool}) << {index, value}
  end

  def add_named(method_name : String, param_name : String, value : Bool) : Nil
    (@named[method_name] ||= [] of {String, Bool}) << {param_name, value}
  end
end
