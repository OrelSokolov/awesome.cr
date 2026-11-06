# Runs enabled guards over collected sources and produces a report.
class Awesome::Runner
  getter config : Config
  getter only : Array(String)?
  getter except : Array(String)?
  getter kind : String?

  def initialize(@config : Config, @only : Array(String)? = nil, @except : Array(String)? = nil,
                 @kind : String? = nil)
  end

  def run(paths : Array(String)) : Report
    only = @only
    except = @except
    kind = @kind
    guards = Guard.all.select do |g|
      next false if kind && g.kind != kind
      next false if only && !only.includes?(g.name)
      next false if except && except.includes?(g.name)
      @config.guard(g.name).enabled?
    end

    sources = collect_files(paths).map { |f| Source.new(f) }
    report = Report.new(sources.size)

    sources.each do |source|
      next unless source.ast
      guards.each do |guard|
        report.add(guard.new.test(source, @config.guard(guard.name)))
      end
    end

    report
  end

  private def collect_files(paths : Array(String)) : Array(String)
    files = if paths.empty?
              @config.includes.flat_map { |g| Dir.glob(g) }
                .select { |f| File.file?(f) }
            else
              paths.flat_map do |p|
                File.directory?(p) ? Dir["#{p.rstrip('/')}/**/*.cr"] : [p]
              end.select { |f| File.file?(f) }
            end
    excluded = @config.excludes.flat_map { |g| Dir.glob(g) }
    (files.uniq - excluded).sort
  end
end
