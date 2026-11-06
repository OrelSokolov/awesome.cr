require "spec"
require "../src/awesome"
require "../src/awesome/guards/*"

def pack_issues(code : String, config_yaml : String? = nil) : Array(Awesome::Issue)
  source = Awesome::Source.new("(test)", code)
  config = config_yaml ? Awesome::GuardConfig.new(YAML.parse(config_yaml)["StructurePacking"]?) : Awesome::GuardConfig.new(nil)
  Awesome::Guards::StructurePacking.new.test(source, config)
end
