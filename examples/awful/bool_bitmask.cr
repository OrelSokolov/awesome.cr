# BoolBitmask — four Bools = 4 bytes; a @[Flags] enum needs 1.
struct Entry
  getter readable : Bool
  getter writable : Bool
  getter executable : Bool
  getter sticky : Bool
end

struct Sprite
  getter visible : Bool # five flags = 5 bytes
  getter flipped : Bool
  getter mirrored : Bool
  getter looping : Bool
  getter animated : Bool
end
