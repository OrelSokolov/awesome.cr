# SubclassNoOverride — inheritance for code reuse, not polymorphism.
# The bad snippet for `awesome doc` and examples/awful; one issue:
# Timer overrides nothing of Clock, it only takes. Alarm overrides
# Clock#zone, so the same hierarchy stays a real polymorphic one (and
# Clock keeps two subclasses — SingleSubclass stays quiet too).
# Self-sufficient in one file — the project index treats it as a
# one-file project.

class Clock
  def now
    Time.utc
  end

  def zone
    "UTC"
  end
end

class Alarm < Clock
  def zone # specialization — its own take
    "UTC+3"
  end
end

class Timer < Clock
  def laps
    [] of Time::Span
  end
end
