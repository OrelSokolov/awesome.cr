# Turns the collected marks into per-line statuses: a fixpoint over
# the syntactic call graph, then one sweep writing line statuses.
#
# Fixpoint (def-level): a def is Red when its body holds a direct
# allocation construct or a call to a Red def; Gray when it holds an
# unresolved call or a call to a Gray def; Green otherwise. States
# start at Green (Red for direct allocators — sticky, `direct?` is
# re-checked every round) and only ever worsen, so the loop converges:
# cycles and self-recursion cost nothing false (two clean methods
# calling each other stay Green), and an allocation anywhere in a
# cycle reddens the whole cycle.
#
# Resolution is by bare name within the scope (like Awesome::Index —
# syntactic, no overload typing): defs written in the project that
# share a name merge, and a call is Red if ANY of them allocates —
# conservative, a false red beats a false green.
#
# Sweep (line-level): every line starts Green; direct marks redden
# their line; each call site gets the worst state of its targets
# (Gray when unresolved); each def line gets its def's state. Marks
# merge by "worse wins", so a line with several marks keeps the worst.
class Awesome::Allocations::Analyzer
  def self.statuses(files : Array(Collector), per_file : Bool) : Array(Collector)
    files.each do |file|
      fill = file.parsable? ? Status::Green : Status::Gray
      file.statuses = Array(Status).new(file.source.code_lines.size, fill)
    end
    if per_file
      files.each { |file| run([file]) }
    else
      run(files)
    end
    files
  end

  private def self.run(files : Array(Collector)) : Nil
    defs = [] of DefInfo
    by_name = Hash(String, Array(Int32)).new { |h, k| h[k] = [] of Int32 }
    files.each do |file|
      next unless file.parsable?
      file.defs.each do |d|
        d.direct = file.direct_red.any? { |line| d.covers?(line) }
        by_name[d.name] << defs.size if d.resolvable
        defs << d
      end
    end

    # Attribute call sites to every def whose range covers their line
    # (ranges nest for def-in-def: an inner def's calls count for the
    # outer one too — conservative, same call is red for both).
    files.each do |file|
      next unless file.parsable?
      file.calls.each do |call|
        file.defs.each do |d|
          d.body_calls << call.name if d.covers?(call.line)
        end
      end
    end

    # The fixpoint itself: def states worsen until stable.
    states = defs.map { |d| d.direct? ? Status::Red : Status::Green }
    changed = true
    while changed
      changed = false
      defs.each_with_index do |d, i|
        worst = d.direct? ? Status::Red : Status::Green
        d.body_calls.each do |name|
          targets = by_name[name]?
          call_state = if targets && !targets.empty?
                         targets.reduce(Status::Green) { |acc, t| acc.worse(states[t]) }
                       else
                         Status::Gray # unresolved: unknown code, needs investigation
                       end
          worst = worst.worse(call_state)
        end
        if states[i] != worst
          states[i] = worst
          changed = true
        end
      end
    end
    defs.each_with_index { |d, i| d.state = states[i] }

    # The line sweep — statuses were pre-filled (Green, or Gray for
    # unparsable files, which skip the loops above).
    files.each do |file|
      next unless file.parsable?
      file.direct_red.each { |line| mark(file, line, Status::Red) }
      file.calls.each do |call|
        targets = by_name[call.name]?
        call_state = if targets && !targets.empty?
                       targets.reduce(Status::Green) { |acc, t| acc.worse(states[t]) }
                     else
                       Status::Gray
                     end
        mark(file, call.line, call_state)
      end
      file.defs.each { |d| mark(file, d.def_line, d.state) }
    end
  end

  private def self.mark(file : Collector, line : Int32, status : Status) : Nil
    return unless line >= 1 && line <= file.statuses.size
    idx = line - 1
    file.statuses[idx] = file.statuses[idx].worse(status)
  end
end
