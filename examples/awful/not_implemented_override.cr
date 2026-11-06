# NotImplementedOverride — a subclass that breaks its parent's promise.
# The bad snippet for `awesome doc` and examples/awful; one issue:
# Line#area only raises, but Shape#area is concrete. Circle keeps the
# promise and gives Shape a second subclass (otherwise SingleSubclass
# would rightly fire too — its case, not this guard's).

class Shape
  def area
    0.0
  end
end

class Circle < Shape
  def area # specializes — the promise holds
    Math::PI * @radius * @radius
  end
end

class Line < Shape
  def area # revokes the promise at runtime
    raise NotImplementedError.new("lines have no area")
  end
end
