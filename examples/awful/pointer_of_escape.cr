# PointerOfEscape — pointerof handed to a storing lib fun.
lib LibStats
  fun register_counter(addr : Int32*) : Void
  fun on_tick(addr : Int32*) : Void
end

LibStats.register_counter(pointerof(@count)) # C keeps the address of a
                                             # GC-managed ivar
LibStats.on_tick(pointerof(ticks))           # same trap, another name

STATE = pointerof(counter) # the field pins the address, not the owner
