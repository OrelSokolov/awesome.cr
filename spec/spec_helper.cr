require "spec"
require "../src/awesome"
require "../src/awesome/guards/*"

# Runs one guard over a snippet and returns its issues. Config, when
# given, is a YAML fragment keyed by the guard name (like awesome.yml's
# `guards:` section for that single guard).
def guard_issues(guard_class : Awesome::Guard.class, code : String, config_yaml : String? = nil) : Array(Awesome::Issue)
  source = Awesome::Source.new("(test)", code)
  config = if config_yaml
    Awesome::GuardConfig.new(YAML.parse(config_yaml)[guard_class.name]?)
  else
    Awesome::GuardConfig.new(nil)
  end
  guard_class.new.test(source, config)
end

def pack_issues(code : String, config_yaml : String? = nil) : Array(Awesome::Issue)
  guard_issues(Awesome::Guards::StructurePacking, code, config_yaml)
end
