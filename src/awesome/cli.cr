require "colorize"

# Command-line interface.
#
#   awesome                  # check the current directory
#   awesome src foo.cr lib/  # check specific paths
#   awesome doc [GUARD]      # show guard documentation
module Awesome::CLI
  USAGE = <<-USAGE
    awesome — is your Crystal code awesome or awful?

    Usage:

      awesome [paths]            Check paths (default: current dir, awesome.yml aware)
      awesome doc [GUARD]        Show documentation for one or all guards
      awesome --version          Show version

    Options:

      --config PATH   Path to awesome.yml (default: ./awesome.yml or ./.awesome.yml)
      --only A,B      Run only these guards
      --except A,B    Run all but these guards
      -h, --help      Show this help
      -v, --version   Show version

    Exit status: 0 — awesome, 1 — awful (issues found), 2 — error.

    Config: awesome.yml in the project root (rubocop.yml-style, guards
    instead of cops). See https://github.com/OrelSokolov/awesome.cr
    USAGE

  def self.run(args : Array(String) = ARGV) : Int32
    paths = [] of String
    config_path = nil
    only = except = nil
    command = :check

    i = 0
    while i < args.size
      case arg = args[i]
      when "doc"        then command = :doc
      when "--config"   then config_path = args[i + 1]? || return usage_error("missing value for --config"); i += 1
      when "--only"     then only = flag_list(args, i)
      when "--except"   then except = flag_list(args, i)
      when "-h", "--help"    then puts USAGE; return 0
      when "-v", "--version" then puts "awesome #{Awesome::VERSION}"; return 0
      when .starts_with?("-") then return usage_error("unknown option: #{arg}")
      else paths << arg
      end
      i += 1
    end

    case command
    when :doc then doc(paths)
    else           check(paths, config_path, only, except)
    end
  end

  def self.check(paths, config_path, only, except) : Int32
    config = Config.load(config_path)
    report = Runner.new(config, only, except).run(paths)
    print_report(report)
    report.awesome? ? 0 : 1
  rescue ex : YAML::ParseException
    STDERR.puts "awesome: config parse error: #{ex.message}"
    2
  end

  def self.doc(names : Array(String)) : Int32
    guards = Awesome::Guard.all.sort_by(&.name)
    unless names.empty?
      guards = guards.select { |g| names.includes?(g.name) }
      if guards.empty?
        STDERR.puts "awesome: no such guard: #{names.join(", ")}"
        STDERR.puts "Available: #{Awesome::Guard.all.map(&.name).join(", ")}"
        return 2
      end
    end
    guards.each do |g|
      puts g.name.colorize.bold
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
    puts "#{report.inspected} inspected, #{report.issues.size} #{"issue".pluralize(report.issues.size)}."
    if report.awesome?
      puts "Your code is awesome.".colorize.light_green.bold
    else
      puts "Your code is awful: #{report.issues.size} #{"issue".pluralize(report.issues.size)}.".colorize.light_red.bold
    end
  end

  private def self.flag_list(args, i) : Array(String)
    (args[i + 1]? || "").split(',').map(&.strip).reject(&.empty?)
  end

  private def self.usage_error(message : String) : Int32
    STDERR.puts "awesome: #{message}"
    STDERR.puts USAGE
    2
  end

  private def self.wrap(text : String, indent : String, width = 78) : String
    padded = text.gsub('\n', " ")
    lines = [] of String
    line = ""
    padded.split(' ').each do |word|
      if (indent.size + line.size + word.size + 1) > width
        lines << line
        line = ""
      end
      line += " " unless line.empty?
      line += word
    end
    lines << line unless line.empty?
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
