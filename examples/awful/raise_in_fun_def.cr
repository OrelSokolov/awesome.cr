# RaiseInFunDef — a raise escaping a C entry point.
fun vib_push(h : Int64) : Int64
  raise "bad handle" # unwinds into the C host that called the fun — UB
end

fun vib_each(count : Int32) : Int32
  count.times { |i|
    raise "row #{i} is corrupt" # nested or not, it escapes the fun
  }
  0
end
