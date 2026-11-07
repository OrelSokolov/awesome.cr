# ToUnsafeEscape — a to_unsafe pointer kept beyond its call.
class Decoder
  def initialize(@blob : Slice(UInt8))
    @raw = @blob.to_unsafe # keeps the pointer, not the slice — one GC
  end                     # cycle later @raw dangles

  def raw_ptr
    return @blob.to_unsafe # the caller outlives @blob's next collection
  end
end

HEADER = "PK".to_unsafe # same trap in a constant
