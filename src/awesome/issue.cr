# A single finding produced by a guard: where, what and why.
class Awesome::Issue
  getter path : String
  getter line : Int32
  getter column : Int32
  getter guard : String
  getter message : String
  getter excerpt : String?

  def initialize(@path : String, @guard : String, @message : String,
                 location : Crystal::Location?, @excerpt : String? = nil)
    @line = location.try(&.line_number) || 0
    @column = location.try(&.column_number) || 0
  end

  def location_string : String
    "#{@path}:#{@line}:#{@column}"
  end
end
