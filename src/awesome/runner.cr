# Runs enabled guards over collected sources and produces a report.
class Awesome::Runner
  getter config : Config
  getter only : Array(String)?
  getter except : Array(String)?
  getter kind : String?
  getter level : String?

  def initialize(@config : Config, @only : Array(String)? = nil, @except : Array(String)? = nil,
                 @kind : String? = nil, @level : String? = nil)
  end

  def run(paths : Array(String)) : Report
    only = @only
    except = @except
    kind = @kind
    # A run at level N executes every guard at level N or below; an
    # explicit `enabled:` in awesome.yml overrides the level in both
    # directions (opt into a single psycho guard, silence a vibecoder one).
    level_index = Guard::LEVELS.index(@level || Guard::DEFAULT_LEVEL).not_nil!
    guards = Guard.all.select do |g|
      next false if kind && g.kind != kind
      next false if only && !only.includes?(g.name)
      next false if except && except.includes?(g.name)
      case @config.guard(g.name).explicit_enabled
      when true  then true
      when false then false
      else            g.level_index <= level_index
      end
    end

    sources = collect_files(paths).map { |f| Source.new(f) }
    report = Report.new(sources.size)

    parsable = sources.select(&.ast)
    parsable.each do |source|
      guards.each do |guard|
        report.add(guard.new.test(source, @config.guard(guard.name)))
      end
    end

    # Per-project pass: one call per guard with the whole collected set
    # — the same file list as above (config excludes apply, so `lib/**`
    # stays out by default and the set covers the current project only).
    guards.each do |guard|
      report.add(guard.new.test_project(parsable, @config.guard(guard.name)))
    end

    report
  end

  private def collect_files(paths : Array(String)) : Array(String)
    self.class.collect_files(@config, paths)
  end

  # File collection shared by guard runs and the `allocations` report:
  # explicit paths (directories walked for *.cr), otherwise the
  # config's includes; the config's excludes apply in both cases.
  def self.collect_files(config : Config, paths : Array(String)) : Array(String)
    files = if paths.empty?
              config.includes.flat_map { |g| Dir.glob(g) }
                .select { |f| File.file?(f) }
            else
              paths.flat_map do |p|
                File.directory?(p) ? Dir["#{p.rstrip('/')}/**/*.cr"] : [p]
              end.select { |f| File.file?(f) }
            end
    excluded = config.excludes.flat_map { |g| Dir.glob(g) }
    (files.uniq - excluded).sort
  end
end
