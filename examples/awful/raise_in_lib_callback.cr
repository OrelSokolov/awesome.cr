# RaiseInLibCallback — raising inside a proc handed to a lib fun.
lib LibWatch
  fun each(cb : Int32 -> Void) : Void
  fun on_error(cb : Int32 -> Void) : Void
end

LibWatch.each(->(row : Int32) {
  raise "row is corrupt" # unwinds through LibWatch's C frames — UB
})

LibWatch.on_error(->(code : Int32) {
  3.times { raise "unstable" } # nested or not, it still unwinds through C
})
