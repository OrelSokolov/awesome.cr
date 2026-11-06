require "yaml"

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

# Root config, loaded from `awesome.yml` (or `.awesome.yml`) in the
# project root. Mirrors the rubocop.yml idea, with guards instead of cops.
#
#   include:
#     - src/**/*.cr
#   exclude:
#     - lib/**
#   level: senior            # vibecoder < senior (default) < psycho
#   guards:
#     StructurePacking:
#       enabled: true
#       check_extern: false
class Awesome::Config
  DEFAULT_INCLUDE = ["**/*.cr"]
  DEFAULT_EXCLUDE = ["lib/**", ".carat/**", ".git/**", "bin/**"]

  getter includes : Array(String)
  getter excludes : Array(String)
  getter guards : Hash(String, YAML::Any)
  getter level : String?

  def initialize(@includes = DEFAULT_INCLUDE, @excludes = DEFAULT_EXCLUDE,
                 @guards = {} of String => YAML::Any, @level = nil)
  end

  def self.locate(dir : String = Dir.current) : String?
    {"awesome.yml", ".awesome.yml"}.each do |name|
      path = File.join(dir, name)
      return path if File.exists?(path)
    end
    nil
  end

  def self.load(path : String? = nil) : self
    path ||= locate
    if path && File.exists?(path)
      from_yaml(File.read(path))
    else
      new
    end
  end

  def self.from_yaml(source : String) : self
    doc = YAML.parse(source)
    includes = any_strings(doc, "include", DEFAULT_INCLUDE)
    excludes = any_strings(doc, "exclude", DEFAULT_EXCLUDE)
    guards = {} of String => YAML::Any
    if raw = doc["guards"]?.try &.as_h?
      raw.each { |name, v| guards[name.to_s] = v }
    end
    level = doc["level"]?.try(&.to_s.presence)
    new(includes, excludes, guards, level)
  end

  def guard(name : String) : GuardConfig
    GuardConfig.new(@guards[name]?)
  end

  private def self.any_strings(doc : YAML::Any, key : String, default) : Array(String)
    v = doc[key]?
    return default unless v
    if arr = v.as_a?
      arr.map(&.to_s)
    else
      default
    end
  end
end
