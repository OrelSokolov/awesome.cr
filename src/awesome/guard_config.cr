# Per-guard settings slice of the config (rubocop-cop-like).
class Awesome::GuardConfig
  def initialize(@raw : YAML::Any?)
  end

  def enabled? : Bool
    bool("enabled", true)
  end

  # Tri-state of the `enabled` key: true/false when the config sets it
  # explicitly, nil when absent. The runner lets an explicit value
  # override the check level in both directions (opt into one psycho
  # guard, or silence one vibecoder guard) while absent guards follow
  # the level filter.
  def explicit_enabled : Bool?
    v = value("enabled")
    v.try &.as_bool?
  end

  def bool(key : String, default : Bool) : Bool
    v = value(key)
    return default unless v
    if (b = v.as_bool?).nil?
      default
    else
      b
    end
  end

  def int(key : String, default : Int32) : Int32
    v = value(key)
    return default unless v
    if (i = v.as_i?).nil?
      default
    else
      i
    end
  end

  def strings(key : String, default : Array(String)) : Array(String)
    v = value(key)
    return default unless v
    if arr = v.as_a?
      arr.map(&.to_s)
    else
      default
    end
  end

  private def value(key : String) : YAML::Any?
    h = @raw.try &.as_h?
    return nil unless h
    h[key]?
  end
end
