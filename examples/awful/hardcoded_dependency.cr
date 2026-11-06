# HardcodedDependency — a class constructing its own dependency.
# The bad snippet for `awesome doc` and examples/awful; one issue:
# Car#start welds in Engine instead of accepting it via initialize.

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
