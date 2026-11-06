# BoolBitmask — four Bools = 4 bytes; a @[Flags] enum needs 1.
struct Entry
  getter readable : Bool
  getter writable : Bool
  getter executable : Bool
  getter sticky : Bool
end
