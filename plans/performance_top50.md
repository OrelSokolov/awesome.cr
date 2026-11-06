# Performance checks catalog — 76 guards

Goal: a prioritized catalog of performance guards in the spirit of
`StructurePacking` — semantic, documented, and **zero false positives**
wherever the pattern is provable from the AST alone. Each entry lists the
bad → good idiom and the FP risk: `[0fp]` (syntactically provable, fire
freely) or `[adv]` (advisory — the pattern is provable but the verdict
depends on context; report, don't scold).

Key constraint (same as `zeroalloc.md`): the parser knows no types, so a
guard fires only when the *shape* of the expression proves the cost
(literal arguments, method names on known receivers, loop context from
`While`/`Block`). Unprovable → skip. False negatives are fine.

Existing guards already cover the struct-layout family:
`StructurePacking`, `BoolBitmask`, `NilableStructField`.

## Priority order (highest value × lowest FP risk first)

1. InterpIntoIo — the #1 hidden allocation in IO code
2. FileReadLines — whole-file slurp for line iteration
3. StringConcatInLoop — O(n²) string building
4. AggregateAfterTransform — intermediate Array just to count/sum
5. SelectCompareZero / SelectFirst — intermediate Array for one answer
6. ArrayConcatInLoop — O(n²) array growth, the classic `arr += [x]`
7. SingleCharStringArg — string arg where a Char is faster
8. MapFlatten / MapCompact — two passes/arrays instead of one
9. UnusedIndex / TimesIndex — index machinery nobody uses
10. LogEagerInterp — eager interpolation in lazy-capable logging

## A. Strings & hidden allocations

| # | Guard | Bad → Good | Risk |
|---|---|---|---|
| 1 | **InterpIntoIo** | `io << "a#{b}c"` / `puts "x=#{x}"` → `io << "a" << b << "c"` — the interpolation expands to `String.interpolation(...)`, an intermediate String per call (see `zeroalloc.md` pattern 1) | `[0fp]` |
| 2 | **StringConcatInLoop** | `s += line` in a loop → `String::Builder` / `IO::Memory` (PLAN.md #3, zeroalloc pattern 2) | `[0fp]` |
| 3 | **StringPlusChain** | `"a" + x + "b"` (3+ operands) → one interpolation or `String::Builder` — each `+` allocates an intermediate String | `[0fp]` |
| 4 | **SingleCharStringArg** | `s.split(",")`, `s.replace("a","b")`, `s.includes?("x")`, `s.starts_with?("x")`, `s.ends_with?("x")`, `s.gsub("a","b")` with single-char String literals → the `Char` overload (no String comparisons) | `[0fp]` |
| 5 | **ToSWithoutIo** | `def to_s : String` → `def to_s(io : IO)` — every caller allocates (zeroalloc pattern 4, config `check_to_s`) | `[0fp]` |
| 6 | **LogEagerInterp** | `log.info "x=#{x}"` → `log.info { "x=#{x}" }` — block form is lazy, disabled levels never build the String | `[0fp]` (receiver named `log`/`logger`) |
| 7 | **JoinMap** | `xs.map { \|x\| "#{x}!" }.join(", ")` → `xs.join(", ") { \|x\| "#{x}!" }` — no intermediate Array of Strings | `[0fp]` (map block must be a single interpolation) |
| 8 | **DowncaseCompare** | `a.downcase == b.downcase` inside a loop → downcase once before the loop | `[adv]` |

## B. Intermediate collections

| # | Guard | Bad → Good | Risk |
|---|---|---|---|
| 9 | **MapFlatten** | `xs.map { }.flatten` → `xs.flat_map { }` (PLAN.md #8) | `[0fp]` |
| 10 | **MapCompact** | `xs.map { }.compact` → `xs.compact_map { }` — one pass, one Array | `[0fp]` |
| 11 | **SelectFirst** | `xs.select { }.first/first?` → `xs.find/find?` — no filtered Array for one element | `[0fp]` |
| 12 | **AggregateAfterTransform** | `xs.map { }.size` → `xs.count { }`; `xs.map { }.sum` → `xs.sum { }` — no intermediate Array | `[0fp]` |
| 13 | **SelectCompareZero** | `xs.select { }.size == 0` → `xs.none? { }`; `.size > 0` → `xs.any? { }` (zeroalloc pattern 3) | `[0fp]` |
| 14 | **SortFirst** | `xs.sort.first/.last` → `xs.min/max`; `xs.sort_by { }.first` → `min_by` — no sorted copy | `[0fp]` |
| 15 | **DupMutate** | `xs.dup.sort!` / `dup.compact!` / `dup.uniq!` / `dup.reverse!` → `xs.sort` (non-bang already returns a copy) | `[0fp]` |
| 16 | **SelfSortReassign** | `x = x.sort/uniq/reverse` → `x.sort!` if nothing else holds a reference (PLAN.md #5) | `[adv]` |
| 17 | **ReverseEach** | `xs.reverse.each { }` → `xs.reverse_each { }` — no reversed copy | `[0fp]` on Array literals, `[adv]` otherwise |
| 18 | **KeysEach** | `h.keys.each { \|k\| }` (block uses only the key) → `h.each` — no key Array | `[adv]` |
| 19 | **EagerIteratorChain** | `xs.map { }.select { }.each { }` → lazy `xs.each.map { }.select { }.each { }` | `[adv]` |
| 20 | **TupleForConstArray** | constant Array literal `COLORS = [1, 2, 3]` only read → Tuple `{1, 2, 3}` — stack, no GC | `[adv]` |

## C. Complexity in loops

| # | Guard | Bad → Good | Risk |
|---|---|---|---|
| 21 | **ArrayConcatInLoop** | `arr = arr + [x]` / `arr += [x]` in a loop → `arr << x` — full copy per iteration, O(n²) | `[0fp]` |
| 22 | **IncludesInLoop** | `ys.includes?(x)` inside an `each` body → build a `Set` once | `[adv]` |
| 23 | **NestedEachEq** | `xs.each { \|x\| ys.each { \|y\| … x == y … } }` → Hash lookup, O(n·m) → O(n) | `[adv]` |
| 24 | **ArrayShiftInLoop** | `shift`/`unshift` with receiver inside a loop → `Deque` (PLAN.md #4) | `[0fp]` |
| 25 | **DeleteInLoop** | `xs.delete(x)` inside a loop → Set membership or one `reject!` pass | `[adv]` |
| 26 | **IndexInLoop** | `xs.index(x)` inside a loop → precomputed Hash index | `[adv]` |
| 27 | **RegexInLoop** | `Regex.new(…)` inside a loop → hoist to a constant (compiles per evaluation) | `[0fp]` |
| 28 | **SortInLoop** | `sort`/`sort_by`/`reverse`/`uniq` re-run every iteration → maintain the invariant incrementally | `[adv]` |

## D. Exceptions as control flow

| # | Guard | Bad → Good | Risk |
|---|---|---|---|
| 29 | **RescueNilable** | `begin arr[i] rescue IndexError` / `h[k]` + `KeyError` / `s.to_i` + `ArgumentError` → `arr[i]?`, `h[k]?`, `to_i?` — exceptions allocate on the heap | `[adv]` (rescue must wrap just the call) |
| 30 | **RescueInLoop** | `rescue` inside a loop body used for flow control → nilable/precondition form | `[adv]` |

## E. Memory layout (companions to the existing family)

| # | Guard | Bad → Good | Risk |
|---|---|---|---|
| 31 | **EnumBaseType** | `enum` whose values are all Int literals ≤ 255, no `@[Extern]` → `base_type UInt8` (default is Int32; 4 bytes → 1) | `[0fp]` (fires only on literal values) |
| 32 | **UnionStructField** | generalization of `NilableStructField`: any multi-member union field in a struct costs `{Int32 tag, max payload}` + a branch — `Int32 \| String` is 16 bytes | `[0fp]` on builtin members |
| 33 | **BigStructByValue** | struct with provable layout and `sizeof > threshold` (config, default 32) passed/returned by value everywhere → memcpy per call; suggest a class or pointer passing | `[adv]` (size is `[0fp]`, verdict isn't) |
| 34 | **NestedStructLayout** | cross-file nested struct layouts so StructurePacking can prove custom-typed fields (ROADMAP) | `[0fp]` |
| 35 | **ClassForImmutableValue** | small immutable class with only `getter`s → `struct` — no heap allocation per instance | `[adv]` (explicitly out of scope in PLAN.md; advisory level) |
| 36 | **HashInitialCapacity** | `Hash(K,V).new` filled with a known count in a loop → `Hash(K,V).new(initial_capacity: n)` | `[adv]` |

## F. Files & IO

| # | Guard | Bad → Good | Risk |
|---|---|---|---|
| 37 | **FileReadLines** | `File.read(p).each_line/.split/.lines`, `File.read_lines(p)`, `io.gets_to_end.split` → `File.each_line(p)` / `io.each_line` — constant memory (PLAN.md #7, zeroalloc pattern 5) | `[0fp]` |
| 38 | **ReadThenSize** | `File.read(p).size` / `.lines.size` → `File.size(p)` — no read at all | `[0fp]` |
| 39 | **FileReadInLoop** | `File.read(p)` inside a loop → read once before it | `[0fp]` |
| 40 | **FileWriteInLoop** | `File.write(p, …)` inside a loop → `File.open(p, "w")` once, `file << …` per iteration | `[0fp]` |
| 41 | **HttpClientPerCall** | `HTTP::Client.new` per request/iteration → reuse the client (connection pool) | `[adv]` |

## G. Iteration & indexing

| # | Guard | Bad → Good | Risk |
|---|---|---|---|
| 42 | **UnusedIndex** | `each_with_index { \|x, i\| }` where `i` never appears in the body → `each` (PLAN.md #6) | `[0fp]` |
| 43 | **TimesIndex** | `xs.size.times { \|i\| … xs[i] … }` → `xs.each { \|x\| }` — no bounds machinery | `[0fp]` (same receiver) |
| 44 | **AnyEqIncludes** | `xs.any? { \|x\| x == y }` → `xs.includes?(y)` | `[0fp]` |
| 45 | **EachBreakFind** | `xs.each { \|x\| break x if … }` → `xs.find { }` | `[adv]` |

## H. Closures, boxing & fibers

| # | Guard | Bad → Good | Risk |
|---|---|---|---|
| 46 | **ProcInLoop** | `->() { … }` literal inside a loop → hoist: each evaluation allocates a Proc (and boxes captured vars) | `[0fp]` |
| 47 | **CapturedLoopVar** | a Proc captures a loop-local variable → a fresh box per iteration; capture by value outside | `[adv]` |
| 48 | **SpawnPerItem** | `spawn` inside `each` without backpressure → bounded channel/semaphore | `[adv]` |
| 49 | **ChannelInLoop** | `Channel.new` inside a loop → create once outside | `[0fp]` |

## I. Micro

| # | Guard | Bad → Good | Risk |
|---|---|---|---|
| 50 | **SizeEqZero** | `xs.size == 0` → `xs.empty?` | `[0fp]` |
| 51 | **DivModPair** | `a / b` and `a % b` on the same operands in one expression → `q, r = a.divmod(b)` | `[adv]` |

## J. Regex & parsing (follow-up)

| # | Guard | Bad → Good | Risk |
|---|---|---|---|
| 52 | **MatchTruthiness** | `if s.match(/re/)` (only truthiness used) → `s.match?(/re/)` — no `Regex::MatchData` allocation | `[0fp]` |
| 53 | **ScanForOne** | `s.scan(/re/).first` → `s.match(/re/)` — scan builds the full Array of matches | `[adv]` |
| 54 | **ParseLiteralInDef** | `URI.parse("…")` / `JSON.parse("…")` on a constant literal inside a def → hoist to a constant | `[0fp]` (literal arg) |

## K. Manual reductions (clippy `manual_*` family)

| # | Guard | Bad → Good | Risk |
|---|---|---|---|
| 55 | **ManualReduce** | `acc = 0; xs.each { acc += f(x) }` → `xs.sum { f(x) }` / `count { }` / `product` — C-level aggregation | `[adv]` |
| 56 | **ManualSelect** | `xs.each { \|x\| ys << x if … }` → `xs.select { }` — one pass, preallocated | `[adv]` |
| 57 | **ManualMemcpy** | `while i < n; dst[i] = src[i]; i += 1; end` → `copy_to`/`copy_from` (memcpy) — clippy `manual_memcpy` | `[adv]` |
| 58 | **MinMaxBy** | `xs.min_by { }` and `xs.max_by { }` on the same receiver nearby → `xs.minmax_by { }` — one pass instead of two | `[0fp]` (same receiver, adjacent) |

## L. Hot-path hoisting & debug leftovers

| # | Guard | Bad → Good | Risk |
|---|---|---|---|
| 59 | **ConstInHotPath** | `Regex.new`, Array/Hash literals, `Random.new`, `Digest::*` instances rebuilt inside a def or loop → hoist to a constant (generalizes 20/27/54) | `[adv]` |
| 60 | **EnvInLoop** | `ENV["X"]` inside a loop → cache in a local before the loop | `[0fp]` |
| 61 | **DebugPrint** | `p` / `pp` / `p!` / `pp!` left in `src/` (not `spec/`) → remove or gate behind a flag | `[0fp]` |
| 62 | **ManualGCCollect** | `GC.collect` outside benchmark/spec code → full stop-the-world pause in production paths | `[0fp]` |

## M. Strings, round two

| # | Guard | Bad → Good | Risk |
|---|---|---|---|
| 63 | **RedundantToS** | `"#{x.to_s}"`, `puts x.to_s`, `io << x.to_s` → drop the `.to_s` — interpolation/`<<` calls it anyway | `[0fp]` |
| 64 | **MaterializeThenEach** | `s.bytes.each` / `s.chars.each` / `s.lines.each` / `s.graphemes.each` → `each_byte` / `each_char` / `each_line` / `each_grapheme` — no intermediate Array | `[0fp]` on String literals, `[adv]` otherwise |
| 65 | **ToSRoundTrip** | `x.to_s.to_i` / `x.to_i.to_s` → use `x` directly | `[adv]` |
| 66 | **SortByReverse** | `xs.sort_by { \|x\| x.k }.reverse` → `sort_by { \|x\| -x.k }` — no reversed copy | `[adv]` |
| 67 | **EmptyStringCompare** | `s == ""` / `s.size == 0` → `s.empty?` | `[0fp]` |

## N. Sleeping, polling & boxing

| # | Guard | Bad → Good | Risk |
|---|---|---|---|
| 68 | **PollLoop** | `while !done?; sleep 0.01; end` → blocking wait (`channel.receive`, `select`) — polling burns wakeups and adds latency | `[adv]` |
| 69 | **BusyFiberLoop** | tight `loop` with no `sleep`/`select`/IO → starves other fibers on the thread (cooperative scheduler) | `[adv]` (careful, shape-based) |
| 70 | **BoxInLoop** | `Box.box(x)` inside a loop → hoist the box | `[0fp]` |
| 71 | **WallClockDelta** | `Time.now - start` for measuring durations → `Time.monotonic` — wall clock jumps (NTP), monotonic doesn't | `[0fp]` (subtraction of two `now` calls) |
| 72 | **RandomPerCall** | `Random.new` inside a def → module-level `RANDOM` constant — re-seeding per call | `[0fp]` |

## O. Hash & dispatch

| # | Guard | Bad → Good | Risk |
|---|---|---|---|
| 73 | **MergeOnePair** | `h.merge({k => v})` with a single pair → `h[k] = v` when `h` is local — no new Hash | `[adv]` |
| 74 | **TransformThenPredicate** | `xs.map { f(x) }.any? { p(x) }` → `xs.any? { p(f(x)) }` — no intermediate Array | `[adv]` |
| 75 | **GroupByTally** | `xs.group_by { }.map { \|k, v\| {k, v.size} }` → `xs.tally_by { }` (verify `tally_by` availability per Crystal version) | `[adv]` |
| 76 | **CaseStringDispatch** | `case` on String literals re-compared per call in hot paths → enum or `Hash(String, Proc)` dispatch | `[adv]` |

## Meta-mechanism: `@[ZeroAlloc]`

From `zeroalloc.md`: a user annotation declaring a hot path; guards then
fire on *any* known-allocating call inside it (interpolations, `.new` on
reference types, `dup/clone/to_a`, `String.build`). Inverts the problem:
instead of the linter guessing hot paths, the code declares them. Pairs
naturally with guards 1–13.

## Cross-cutting refactors needed before the flood

- Extract the triplicated struct-field machinery (`PRIMITIVES`,
  `FIELD_MACROS`, `each_field_type`, annotation pairing) into a shared
  `Awesome::StructFields` helper — three copies exist today, fifty guards
  must not make it fifty.
- Extract the loop-context visitor (While/Until/iterator-Call-with-Block)
  described in PLAN.md phase 2 — ~10 guards above need it.
- `examples/` bad-fixtures per pattern (zeroalloc.md already specifies
  this) become the regression baseline as guards multiply.
