# StructurePacking — UInt8, Int64, UInt8: padding eats 16 bytes.
# Fields must go by decreasing alignment (largest first).
struct Frame
  getter tag : UInt8
  getter id : Int64
  getter flags : UInt8
end
