require "option_parser"
require "colorize"

# Command-line interface.
#
#   awesome                  # check the current directory (all guards)
#   awesome speed src foo.cr # check paths with speed guards only
#   awesome memory lib/      # check paths with memory guards only
#   awesome doc [GUARD]      # show guard documentation
module Awesome::CLI
  COMMANDS = {"doc", "speed", "memory"}

  def self.run(args : Array(String) = ARGV) : Int32
    argv = args.dup
    first = argv.first?
    command = (first && COMMANDS.includes?(first)) ? argv.shift : "check"

    paths = [] of String
    config_path = nil
    only = except = nil
    finished = false
    code = 0

    parser = OptionParser.new do |p|
      p.banner = <<-BANNER
        awesome — is your Crystal code awesome or awful?

        Usage:

          awesome [paths]            Check paths with all guards (default: current dir, awesome.yml aware)
          awesome speed [paths]      Check paths with speed guards only
          awesome memory [paths]     Check paths with memory guards only
          awesome doc [GUARD]        Show documentation for one or all guards

        Options:
        BANNER

      p.on("--config PATH", "Path to awesome.yml (default: ./awesome.yml or ./.awesome.yml)") { |v| config_path = v }
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

    paths = argv

    case command
    when "doc" then doc(paths)
    else           check(paths, config_path, only, except, command)
    end
  end

  def self.check(paths, config_path, only, except, command) : Int32
    config = Config.load(config_path)
    kind = command.in?("speed", "memory") ? command : nil
    report = Runner.new(config, only, except, kind).run(paths)
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
      puts "#{g.name} (#{g.kind})".colorize.bold
      puts wrap(g.short_description, indent: "  ")
      puts "  Good example:"
      puts indent(g.good_example, "    ")
      puts "  Bad example:"
      puts indent(g.bad_example, "    ")
      puts
    end
    0
  end

  def self.print_report(report : Report) : Nil
    report.sort!
    report.issues.each do |issue|
      puts issue.location_string.colorize.light_cyan
      puts "[#{issue.guard}] #{issue.message}".colorize.light_yellow
      if excerpt = issue.excerpt
        puts "> #{excerpt}".colorize.light_gray
        puts
      end
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

  private def self.usage_error(message : String, parser : OptionParser) : Int32
    STDERR << "awesome: " << message << '\n'
    STDERR.puts parser
    2
  end

  private def self.wrap(text : String, indent : String, width = 78) : String
    padded = text.gsub('\n', " ")
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
