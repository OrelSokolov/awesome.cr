# HardcodedDependency — a class constructing its own dependency.
# The bad snippet for `awesome doc` and examples/awful; two issues:
# Car#start welds in Engine, and Fleet#deploy welds in Car — the same
# construction one level up. Both accept the dependency via
# initialize instead and it becomes substitutable in tests.

class Engine
  def run
    puts "vroom"
  end
end

class Car
  def start
    engine = Engine.new # hardcoded — can't be substituted in tests
    engine.run
  end
end

class Fleet
  def deploy
    car = Car.new # hardcoded again — inject the Car instead
    car.start
  end
end
