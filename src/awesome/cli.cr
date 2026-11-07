require "option_parser"
require "colorize"

# Command-line interface.
#
#   awesome                  # check the current directory (all guards)
#   awesome speed src foo.cr # check paths with speed guards only
#   awesome memory lib/      # check paths with memory guards only
#   awesome code src/        # check paths with code guards only
#   awesome --level psycho   # opt into micro-optimization guards too
#   awesome doc [GUARD]      # show guard documentation
#   awesome guards           # list registered guards — total, by level and kind
module Awesome::CLI
  COMMANDS = {"doc", "speed", "memory", "code", "guards"}

  def self.run(args : Array(String) = ARGV) : Int32
    argv = args.dup
    first = argv.first?
    command = (first && COMMANDS.includes?(first)) ? argv.shift : "check"

    # The help banner and option descriptions are localized, so the
    # language must be known before the parser is built — pre-scan
    # --lang (the parser validates it fully after parse).
    Awesome::I18n.locale = Awesome::I18n.resolve(pre_scan_lang(argv))

    paths = [] of String
    config_path = nil
    only = except = level = lang = nil
    finished = false
    code = 0

    # doc/guards print messages too — resolve the locale up front
    # (check() refines it with awesome.yml's `lang:` later).
    parser = OptionParser.new do |p|
      p.banner = Awesome::I18n.t("cli.banner")

      p.on("--config PATH", Awesome::I18n.t("cli.opt.config")) { |v| config_path = v }
      p.on("--level NAME", Awesome::I18n.t("cli.opt.level", levels: Awesome::Guard::LEVELS.join(", "), default: Awesome::Guard::DEFAULT_LEVEL)) { |v| level = v }
      p.on("--only A,B", Awesome::I18n.t("cli.opt.only")) { |v| only = split_list(v) }
      p.on("--except A,B", Awesome::I18n.t("cli.opt.except")) { |v| except = split_list(v) }
      p.on("--lang LOCALE", Awesome::I18n.t("cli.opt.lang", languages: Awesome::I18n::LOCALES.join(", "), default: Awesome::I18n::DEFAULT_LOCALE)) { |v| lang = v }
      p.on("-v", "--version", "Show version") do
        STDOUT << "awesome " << Awesome::VERSION << '\n'
        finished = true
      end
      p.on("-h", "--help", "Show this help") do
        puts p
        finished = true
      end
      p.invalid_option { |opt| code = usage_error(Awesome::I18n.t("cli.errors.unknown_option", option: opt), p); finished = true }
      p.missing_option { |opt| code = usage_error(Awesome::I18n.t("cli.errors.missing_value", option: opt), p); finished = true }
    end
    parser.parse(argv)
    return code if finished
    if level && !Awesome::Guard::LEVELS.includes?(level)
      return usage_error(Awesome::I18n.t("cli.errors.unknown_level", level: level, available: Awesome::Guard::LEVELS.join(", ")), parser)
    end
    if lang && !Awesome::I18n::LOCALES.includes?(lang)
      return usage_error(Awesome::I18n.t("cli.errors.unknown_lang", lang: lang, available: Awesome::I18n::LOCALES.join(", ")), parser)
    end

    Awesome::I18n.locale = Awesome::I18n.resolve(lang)
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
      STDERR << "awesome: " << Awesome::I18n.t("cli.errors.unknown_level_config",
        level: level, available: Awesome::Guard::LEVELS.join(", ")) << '\n'
      return 2
    end
    # Same priority for the language; absent everywhere — take LANG's hint.
    if config.lang && !Awesome::I18n::LOCALES.includes?(config.lang)
      STDERR << "awesome: " << Awesome::I18n.t("cli.errors.unknown_lang_config",
        lang: config.lang, available: Awesome::I18n::LOCALES.join(", ")) << '\n'
      return 2
    end
    Awesome::I18n.locale = (config.lang || Awesome::I18n.locale)
    # Any command other than "check" is a kind filter (speed/memory/code).
    kind = command == "check" ? nil : command
    report = Runner.new(config, only, except, kind, level).run(paths)
    print_report(report)
    report.awesome? ? 0 : 1
  rescue ex : YAML::ParseException
    STDERR << "awesome: " << Awesome::I18n.t("cli.errors.config_parse", message: ex.message) << '\n'
    2
  end

  def self.doc(names : Array(String)) : Int32
    guards = Awesome::Guard.all.sort_by(&.name)
    unless names.empty?
      guards = guards.select { |g| names.includes?(g.name) }
      if guards.empty?
        STDERR << "awesome: " << Awesome::I18n.t("cli.errors.no_such_guard", names: names.join(", ")) << '\n'
        STDERR << Awesome::I18n.t("cli.errors.available", guards: Awesome::Guard.all.map(&.name).join(", ")) << '\n'
        return 2
      end
    end
    guards.each do |g|
      puts "#{g.name} (#{g.kind}, #{g.level}, #{g.severity})".colorize.bold
      puts wrap(g.short_description, indent: "  ")
      STDOUT << "  " << Awesome::I18n.t("doc.good_example") << '\n'
      puts indent(g.good_example, "    ")
      STDOUT << "  " << Awesome::I18n.t("doc.bad_example") << '\n'
      puts indent(g.bad_example, "    ")
      puts
    end
    0
  end

  # Reference listing: how many guards are registered in total and
  # which ones, grouped by check level (vibecoder / senior / psycho),
  # then by kind (speed / memory / code), each guard with its short
  # description right in the list. Empty groups are skipped.
  KIND_ORDER = {"speed", "memory", "code"}

  def self.guards_reference : Int32
    all = Awesome::Guard.all
    header = Awesome::I18n.t("cli.guards.registered",
      version: Awesome::VERSION, count: all.size)
    STDOUT << header << '\n' << '\n'
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
    summary = Awesome::I18n.t("report.summary",
      inspected: Awesome::I18n.t("report.inspected", count: report.inspected),
      issues: Awesome::I18n.t("report.issues", count: count))
    STDOUT << summary << ".\n"
    if report.awesome?
      puts Awesome::I18n.t("report.awesome").colorize.light_green.bold
    else
      puts Awesome::I18n.t("report.awful",
        issues: Awesome::I18n.t("report.issues", count: report.issues.size)).colorize.light_red.bold
    end
  end

  private def self.split_list(value : String) : Array(String)
    value.split(',').map(&.strip).reject(&.empty?)
  end

  # `--lang VALUE` / `--lang=VALUE` before any parsing, see run().
  private def self.pre_scan_lang(argv : Array(String)) : String?
    argv.each_with_index do |arg, i|
      if arg == "--lang"
        return argv[i + 1]?
      elsif arg.starts_with?("--lang=")
        return arg.split('=', 2)[1]?
      end
    end
    nil
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
