# GodClass — one class with too many responsibilities.
# The bad snippet for `awesome doc` and examples/awful; one issue:
# Monster crosses the max_ivars threshold (10) with a method on top.
# 9 ivars would stay quiet — the guard points at outliers only.

class Monster
  property hp : Int32
  property mp : Int32
  property level : Int32
  property xp : Int32
  property gold : Int32
  property attack : Int32
  property defense : Int32
  property speed : Int32
  property luck : Int32
  property alignment : Int32

  def roar
    puts "RAWR"
  end
end
