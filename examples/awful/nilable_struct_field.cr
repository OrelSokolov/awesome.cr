# NilableStructField — a nilable field is a tagged union, not a payload.
struct Session
  getter id : Int64? # 16 bytes + a branch, not 8
  getter closed : Bool
end

struct Slot
  getter label : String? # pointer payload, still tagged
  getter weight : Int32
end
