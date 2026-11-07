require "spec"
require "../src/awesome"
require "../src/awesome/guards/*"

# Specs assert English message text — pin the locale (and the env it
# could be detected from) so a ru_RU machine runs the suite the same.
ENV.delete("LC_ALL")
ENV["LANG"] = "en_US.UTF-8"
Spec.before_each { Awesome::I18n.locale = "en" }

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

# Runs one guard's per-project pass over a set of snippets (one Source
# per string) — the test_project twin of `guard_issues`. Config, when
# given, is a YAML fragment keyed by the guard name.
def guard_project_issues(guard_class : Awesome::Guard.class, codes : Array(String),
                         config_yaml : String? = nil) : Array(Awesome::Issue)
  sources = codes.map_with_index { |code, i| Awesome::Source.new("(test#{i})", code) }
  config = if config_yaml
    Awesome::GuardConfig.new(YAML.parse(config_yaml)[guard_class.name]?)
  else
    Awesome::GuardConfig.new(nil)
  end
  guard_class.new.test_project(sources, config)
end
