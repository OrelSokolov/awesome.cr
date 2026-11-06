# NilableStructField — Int64? is a 16-byte tagged union, not 8.
struct Session
  getter id : Int64?
  getter closed : Bool
end
