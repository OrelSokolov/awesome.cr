# MemoryLeak — LibArena.malloc is never paired with a free.
lib LibArena
  fun malloc(size : Int32) : Void*
  fun free(ptr : Void*)
end

class Ring
  def initialize
    @buffer = LibArena.malloc(4096) # LibArena.free is never called
  end
end
