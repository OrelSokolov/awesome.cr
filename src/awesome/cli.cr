require "option_parser"
require "colorize"

# Command-line interface.
#
#   awesome                  # check the current directory (all guards)
#   awesome speed src foo.cr # check paths with speed guards only
#   awesome memory lib/      # check paths with memory guards only
#   awesome smell src/       # check paths with smell guards only
#   awesome --level psycho   # opt into micro-optimization guards too
#   awesome doc [GUARD]      # show guard documentation
#   awesome guards           # list registered guards — total, by level and kind
module Awesome::CLI
  COMMANDS = {"doc", "speed", "memory", "smell", "guards"}

  def self.run(args : Array(String) = ARGV) : Int32
    argv = args.dup
    first = argv.first?
    command = (first && COMMANDS.includes?(first)) ? argv.shift : "check"

    paths = [] of String
    config_path = nil
    only = except = level = nil
    finished = false
    code = 0

    parser = OptionParser.new do |p|
      p.banner = <<-BANNER
        awesome — is your Crystal code awesome or awful?

        Usage:

          awesome [paths]            Check paths with all guards (default: current dir, awesome.yml aware)
          awesome speed [paths]      Check paths with speed guards only
          awesome memory [paths]     Check paths with memory guards only
          awesome smell [paths]      Check paths with smell guards only
          awesome doc [GUARD]        Show documentation for one or all guards
          awesome guards             List registered guards (total, by level and kind)

        Options:
      BANNER

      p.on("--config PATH", "Path to awesome.yml (default: ./awesome.yml or ./.awesome.yml)") { |v| config_path = v }
      p.on("--level NAME", "Check up to this level: #{Awesome::Guard::LEVELS.join(", ")} (default: #{Awesome::Guard::DEFAULT_LEVEL})") { |v| level = v }
      p.on("--only A,B", "Run only these guards") { |v| only = split_list(v) }
      p.on("--except A,B", "Run all but these guards") { |v| except = split_list(v) }
      p.on("-v", "--version", "Show version") do
        STDOUT << "awesome " << Awesome::VERSION << '\n'
        finished = true
      end
      p.on("-h", "--help", "Show this help") do
        puts p
        finished = true
      end
      p.invalid_option { |opt| code = usage_error("unknown option: #{opt}", p); finished = true }
      p.missing_option { |opt| code = usage_error("missing value for #{opt}", p); finished = true }
    end
    parser.parse(argv)
    return code if finished
    if level && !Awesome::Guard::LEVELS.includes?(level)
      return usage_error("unknown level: #{level} (available: #{Awesome::Guard::LEVELS.join(", ")})", parser)
    end

    paths = argv

    case command
    when "doc"    then doc(paths)
    when "guards" then guards_reference
    else               check(paths, config_path, only, except, command, level)
    end
  end

  def self.check(paths, config_path, only, except, command, cli_level = nil) : Int32
    config = Config.load(config_path)
    # CLI beats awesome.yml beats the built-in default.
    level = cli_level || config.level || Awesome::Guard::DEFAULT_LEVEL
    unless Awesome::Guard::LEVELS.includes?(level)
      STDERR << "awesome: unknown level in awesome.yml: " << level \
        << " (available: " << Awesome::Guard::LEVELS.join(", ") << ")\n"
      return 2
    end
    # Any command other than "check" is a kind filter (speed/memory/smell).
    kind = command == "check" ? nil : command
    report = Runner.new(config, only, except, kind, level).run(paths)
    print_report(report)
    report.awesome? ? 0 : 1
  rescue ex : YAML::ParseException
    STDERR << "awesome: config parse error: " << ex.message << '\n'
    2
  end

  def self.doc(names : Array(String)) : Int32
    guards = Awesome::Guard.all.sort_by(&.name)
    unless names.empty?
      guards = guards.select { |g| names.includes?(g.name) }
      if guards.empty?
        STDERR << "awesome: no such guard: " << names.join(", ") << '\n'
        STDERR << "Available: " << Awesome::Guard.all.map(&.name).join(", ") << '\n'
        return 2
      end
    end
    guards.each do |g|
      puts "#{g.name} (#{g.kind}, #{g.level}, #{g.severity})".colorize.bold
      puts wrap(g.short_description, indent: "  ")
      puts "  Good example:"
      puts indent(g.good_example, "    ")
      puts "  Bad example:"
      puts indent(g.bad_example, "    ")
      puts
    end
    0
  end

  # Reference listing: how many guards are registered in total and
  # which ones, grouped by check level (vibecoder / senior / psycho),
  # then by kind (speed / memory / smell), each guard with its short
  # description right in the list. Empty groups are skipped.
  KIND_ORDER = {"speed", "memory", "smell"}

  def self.guards_reference : Int32
    all = Awesome::Guard.all
    STDOUT << "awesome " << Awesome::VERSION << " — " << all.size << ' ' \
      << "guard".pluralize(all.size) << " registered" << '\n' << '\n'
    Awesome::Guard::LEVELS.each do |level|
      level_guards = all.select(&.level.==(level))
      next if level_guards.empty?
      STDOUT << level << " (" << level_guards.size << "):" << '\n'
      kinds = level_guards.map(&.kind).uniq
      kinds = kinds.sort_by { |k| {KIND_ORDER.index(k) || KIND_ORDER.size, k} }
      kinds.each do |kind|
        guards = level_guards.select(&.kind.==(kind)).sort_by(&.name)
        STDOUT << "  " << kind << " (" << guards.size << "):" << '\n'
        guards.each do |g|
          STDOUT << wrap("#{g.name} — #{g.short_description}", indent: "    ") << '\n'
        end
      end
      puts
    end
    0
  end

  def self.print_report(report : Report) : Nil
    report.sort!
    report.issues.each do |issue|
      puts issue.location_string.colorize.light_cyan
      if excerpt = issue.excerpt
        puts "> #{excerpt}".colorize.light_gray
      end
      puts "[#{issue.guard}] #{issue.message}".colorize(severity_color(issue.guard))
      puts if issue.excerpt
    end
    count = report.issues.size
    STDOUT << report.inspected << " inspected, " << count << ' ' \
      << "issue".pluralize(count) << ".\n"
    if report.awesome?
      puts "Your code is awesome.".colorize.light_green.bold
    else
      puts "Your code is awful: #{report.issues.size} #{"issue".pluralize(report.issues.size)}.".colorize.light_red.bold
    end
  end

  private def self.split_list(value : String) : Array(String)
    value.split(',').map(&.strip).reject(&.empty?)
  end

  # Severity → report color: bugs light red, warnings light yellow
  # (the historical one), style nits light magenta.
  SEVERITY_COLORS = {
    "bug"     => :light_red,
    "warning" => :light_yellow,
    "style"   => :light_magenta,
  }

  private def self.severity_color(guard_name : String)
    severity = Awesome::Guard.all.find { |g| g.name == guard_name }
      .try(&.severity) || Awesome::Guard::DEFAULT_SEVERITY
    SEVERITY_COLORS[severity]? || :light_yellow
  end

  private def self.usage_error(message : String, parser : OptionParser) : Int32
    STDERR << "awesome: " << message << '\n'
    STDERR.puts parser
    2
  end

  private def self.wrap(text : String, indent : String, width = 78) : String
    # Squeeze whitespace runs: SHORT_DESCRIPTION heredocs are indented
    # like the class body around them, so naive newline-to-space turns
    # those indents into stray double spaces.
    padded = text.gsub(/\s+/, " ").strip
    lines = [] of String
    line = IO::Memory.new
    padded.split(' ').each do |word|
      if (indent.size + line.size + word.size + 1) > width
        lines << line.to_s
        line.clear
      end
      line << ' ' unless line.size.zero?
      line << word
    end
    lines << line.to_s unless line.size.zero?
    lines.map { |l| "#{indent}#{l}" }.join('\n')
  end

  private def self.indent(text : String, prefix : String) : String
    text.split('\n').map { |l| "#{prefix}#{l}" }.join('\n')
  end
end

class String
  def pluralize(count : Int32)
    count == 1 ? self : "#{self}s"
  end
end
