# UnpinnedLibCallback — a closure handed to a storing lib fun inline.
lib LibUi
  fun on_click(cb : Int32 -> Void) : Void
  fun set_logger(cb : Int32 -> Void) : Void
end

LibUi.on_click(->(button : Int32) {
  Counter.add(button) # fires long after the call returned — and after
})                    # the GC freed the unreferenced closure

LibUi.set_logger(->(level : Int32) {
  Log.write(level) # same: stored on the C side, dead on ours
})

LibUi.set_logger(Box.box(Logger.new)) # the box is collectable too
