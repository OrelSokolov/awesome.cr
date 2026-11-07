# CliStdoutEpipe — a CLI that dies when its stdout reader walks away.
#
# `foo | head`: head takes its lines and exits, the next write(2) into
# the dead pipe returns EPIPE, the runtime raises `IO::Error`, and the
# process dies mid-report — truncated output, a trace on stderr, a
# garbage exit status. The same happens with `| less` on quit, or an
# editor's preview buffer that stops reading. The fix is two lines at
# the entry point: rescue `IO::Error`, exit 0 when the errno is EPIPE
# (any other `IO::Error` stays an error). Precedent: CRASH-001 —
# awesome itself died on `awesome | head` until bin/awesome.cr learned
# the rescue.
#
# Where the evidence is (all syntactic, per file):
#   * a collected file that writes to STDOUT at top level (`puts`,
#     `print`, `STDOUT <<` …) — a script;
#   * a binary declared in shard.yml (`binaries:` → `main:`) — the
#     entry point the shard actually ships. bin/** sits in the default
#     exclude set, so the runner never collects these files; the
#     project pass reads them from disk itself. Here any top-level
#     call except `require` is the entry flow — a binary that only
#     forwards to its library (`exit Foo::CLI.run(ARGV)`) still needs
#     the rescue.
#
# Handling is checked over the whole file: a `rescue` naming
# `IO::Error`, or a reference to `Errno::EPIPE` / `Signal::PIPE`
# anywhere in it silences the guard — syntax can't tell which rescue
# actually wraps which write, and a `Signal.trap(Signal::PIPE)` guards
# the whole process anyway.
class Awesome::Guards::CliStdoutEpipe < Awesome::Guard
  KIND              = "code"
  LEVEL             = "psycho" # opt-in: matters for shipped binaries, noise on scripts
  SEVERITY          = "style"  # the exit is ugly, the logic is intact — a UX wart, not a bug
  SHORT_DESCRIPTION = <<-TEXT
    Checks that a CLI survives its stdout reader leaving — `foo | head`
    must not die with `IO::Error: Broken pipe` mid-output. Fires on a
    file with top-level output (puts, print, STDOUT << …) or on a
    binary declared in shard.yml, when nothing in the file handles
    EPIPE (a `rescue IO::Error`, `Errno::EPIPE`, `Signal::PIPE`). The
    fix is two lines at the entry point: rescue IO::Error, exit 0 on
    EPIPE.
    TEXT

  GOOD_EXAMPLE = <<-CODE
    require "../src/tool"
    begin
      exit Tool::CLI.run(ARGV)
    rescue e : IO::Error
      exit(e.os_error == Errno::EPIPE ? 0 : 1) # reader gone — not an error
    end
    CODE

  BAD_EXAMPLE = <<-CODE
    require "../src/tool"
    exit Tool::CLI.run(ARGV) # `tool | head` dies with IO::Error mid-output
    CODE

  # Kernel print family: zero-receiver calls that write to STDOUT.
  OUTPUT_CALLS = {"puts", "print", "p", "pp", "printf"}

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    [] of Awesome::Issue # evidence spans the file (and shard.yml) — the project pass decides
  end

  def test_project(sources : Array(Awesome::Source), config : Awesome::GuardConfig) : Array(Awesome::Issue)
    binaries = shard_binaries
    binary_paths = binaries.map { |path| File.expand_path(path) }
    issues = [] of Awesome::Issue

    # Collected files: only top-level output proves a CLI (a script);
    # declared binaries are checked below with their entry flow.
    sources.each do |source|
      next if binary_paths.includes?(File.expand_path(source.path))
      issues.concat(check_script(source))
    end

    # Declared entry points, read from disk: bin/** is excluded from
    # the collected set by default, so shard.yml is where the shard
    # says what it ships.
    binaries.each do |path|
      issues.concat(check_binary(Awesome::Source.new(path)))
    end
    issues
  end

  # A script: top-level output proves a CLI. Silent when the file
  # handles EPIPE or shows no top-level write; otherwise one issue
  # anchored at the first one.
  private def check_script(source : Awesome::Source) : Array(Awesome::Issue)
    return [] of Awesome::Issue unless ast = source.ast
    return [] of Awesome::Issue if handles_epipe?(ast)

    points = EntryPoints.new
    ast.accept(points)
    report(source, "top-level output, but nothing in the file handles EPIPE", points.output_calls.first?)
  end

  # A declared binary: any top-level call except require is the entry
  # flow — a binary that only forwards to its library
  # (`exit Foo::CLI.run(ARGV)`) still needs the rescue. Anchored at the
  # first one.
  private def check_binary(source : Awesome::Source) : Array(Awesome::Issue)
    return [] of Awesome::Issue unless ast = source.ast
    return [] of Awesome::Issue if handles_epipe?(ast)

    points = EntryPoints.new
    ast.accept(points)
    report(source, "shard.yml declares this binary, but nothing here handles EPIPE", points.entry_calls.first?)
  end

  private def report(source : Awesome::Source, what : String,
                     anchor : Crystal::Call?) : Array(Awesome::Issue)
    return [] of Awesome::Issue unless anchor
    location = anchor.location
    [Awesome::Issue.new(
      source.path,
      "CliStdoutEpipe",
      Awesome::I18n.t("guards.CliStdoutEpipe.main", what: what),
      location,
      source.excerpt_at(location.try(&.line_number) || 0)
    )]
  end

  # Whole-file handling evidence: a `rescue` naming IO::Error, or a
  # reference to Errno::EPIPE / Signal::PIPE (a trap or an errno check
  # inside a rescue both count).
  private def handles_epipe?(ast : Crystal::ASTNode) : Bool
    finder = Handler.new
    ast.accept(finder)
    finder.handles?
  end

  # Entry points declared in shard.yml (`binaries:` → name → `main:`),
  # read from the working directory — the runner's file set excludes
  # bin/** by default, so declared binaries are pulled in here instead.
  # No shard.yml / no `binaries:` key → no CLI to check — silent.
  private def shard_binaries : Array(String)
    doc = YAML.parse(File.read("shard.yml"))
    bins = doc["binaries"]?.try &.as_h?
    return [] of String unless bins

    paths = [] of String
    bins.each_value do |value|
      main = value.as_h?.try(&.["main"]?).try(&.to_s) || value.as_s?
      next unless main
      paths << main if File.file?(main)
    end
    paths
  rescue
    [] of String
  end

  # Top-level calls of a file: the entry flow (any call except
  # `require`) and output calls (the Kernel print family, or any call
  # on the STDOUT constant). "Top level" — not inside a def, block,
  # proc, class, module, lib or macro: those run on someone else's
  # schedule, not the file's.
  private class EntryPoints < Crystal::Visitor
    getter entry_calls = [] of Crystal::Call
    getter output_calls = [] of Crystal::Call

    @depth = 0

    def visit(node : Crystal::Def | Crystal::Block | Crystal::ProcLiteral |
                     Crystal::ClassDef | Crystal::ModuleDef | Crystal::LibDef | Crystal::Macro)
      @depth += 1
      true
    end

    def end_visit(node : Crystal::Def | Crystal::Block | Crystal::ProcLiteral |
                         Crystal::ClassDef | Crystal::ModuleDef | Crystal::LibDef | Crystal::Macro)
      @depth -= 1
    end

    def visit(node : Crystal::Call)
      if @depth.zero?
        entry_calls << node unless node.name == "require"
        output_calls << node if output?(node)
      end
      true
    end

    # Fallback: redefining `visit` in a subclass replaces the base
    # class's overloads, so re-enable traversal for everything else.
    def visit(node : Crystal::ASTNode)
      true
    end

    private def output?(call : Crystal::Call) : Bool
      return call.name.in?(OUTPUT_CALLS) if call.obj.nil?
      obj = call.obj
      obj.is_a?(Crystal::Path) && obj.to_s == "STDOUT"
    end
  end

  # Does the file handle EPIPE anywhere: a `rescue` clause naming
  # IO::Error (types are Path/Generic nodes, compared as written), or a
  # constant reference to Errno::EPIPE / Signal::PIPE.
  private class Handler < Crystal::Visitor
    getter? handles = false

    def visit(node : Crystal::Rescue)
      node.types.try { |types| @handles ||= types.any?(&.to_s.includes?("IO::Error")) }
      true
    end

    def visit(node : Crystal::Path)
      written = node.to_s
      @handles ||= written.ends_with?("Errno::EPIPE") || written.ends_with?("Signal::PIPE")
      true
    end

    def visit(node : Crystal::ASTNode)
      true
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::CliStdoutEpipe
