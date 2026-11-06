# StructurePacking — fields must go by decreasing alignment.
struct Frame
  getter tag : UInt8   # narrow first…
  getter id : Int64    # …forces padding around the Int64
  getter flags : UInt8
end

struct Packet
  getter kind : UInt8   # 24 bytes as written (13 padding)
  getter seq : UInt64   # 16 when packed: UInt64, UInt16, UInt8
  getter length : UInt16
end
