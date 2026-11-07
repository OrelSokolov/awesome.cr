require "yaml"

# Root config, loaded from `awesome.yml` (or `.awesome.yml`) in the
# project root. Mirrors the rubocop.yml idea, with guards instead of cops.
# The per-guard settings slice lives in guard_config.cr.
#
#   include:
#     - src/**/*.cr
#   exclude:
#     - lib/**
#   level: senior            # vibecoder < senior (default) < psycho
#   lang: ru                 # message language: en (default), ru
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
  getter lang : String?

  def initialize(@includes = DEFAULT_INCLUDE, @excludes = DEFAULT_EXCLUDE,
                 @guards = {} of String => YAML::Any, @level = nil, @lang = nil)
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
    lang = doc["lang"]?.try(&.to_s.presence)
    new(includes, excludes, guards, level, lang)
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
