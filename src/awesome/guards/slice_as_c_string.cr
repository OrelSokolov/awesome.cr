# SliceAsCString — `x.to_unsafe` passed where the C side expects a
# NUL-terminated string, with no length argument in sight.
#
# `LibCfg.read(slice.to_unsafe)` hands C a raw buffer pointer. If the
# receiver is a String, the bytes are NUL-terminated and C reading them
# as a string is fine; if it is a Slice (or StaticArray), they are
# NOT — C's strlen/read runs past the buffer end, which is undefined
# behaviour: usually garbage, occasionally a segfault, always far from
# the call. The AST cannot tell String from Slice at the receiver, so
# this is deliberately a "requires attention" marker (style), not a
# bug verdict: the guard fires only when nothing at the call site says
# a length travels with the pointer (no `size`/`bytesize`/`length`/
# `count`/`cap` argument) — that is exactly the shape where a Slice
# receiver means an overread.
#
# Safer alternatives: pass the length next to the pointer
# (`LibCfg.read_n(buf.to_unsafe, buf.size)`), or make a terminated copy
# (`String.new(slice).to_unsafe` — allocates, but the contract is
# explicit), or bind the fun as taking `(data : UInt8*, len : Int32)`
# in the first place.
#
# A fun must be declared in this file to be checked: the parameter
# types (`UInt8*`/`Int8*`/`Char*`) come from its own `lib` declaration.
# Shims bound elsewhere (Lib-prefixed without a declaration) have an
# unknown signature — a false negative by design.
class Awesome::Guards::SliceAsCString < Awesome::Guard
  KIND              = "memory"
  LEVEL             = "senior" # on by default: attention marker, not a bug
  SEVERITY          = "style"  # suspicion — String receivers are fine here
  SHORT_DESCRIPTION = <<-TEXT
    Checks that `x.to_unsafe` passed to a `UInt8*`/`Int8*`/`Char*`
    parameter of a lib fun travels with a length argument. A String's
    bytes are NUL-terminated, a Slice's are not — C reading the
    pointer as a string overreads the buffer (UB). If the receiver
    might be a Slice, pass `x.size` alongside, copy via
    `String.new(x)`, or bind the fun as `(data : UInt8*, len : Int32)`.
    TEXT

  GOOD_EXAMPLE = <<-CODE
    lib LibCfg
      fun read_n(data : UInt8*, len : Int32) : Int32
    end

    LibCfg.read_n(buf.to_unsafe, buf.size) # pointer and its length
    CODE

  BAD_EXAMPLE = <<-CODE
    lib LibCfg
      fun read(name : UInt8*) : Int32
    end

    LibCfg.read(buf.to_unsafe) # buf is a Slice — no NUL, no length
    CODE

  # Argument expressions whose presence says a length travels with the
  # pointer (`read(buf.to_unsafe, buf.size)` is explicit and safe).
  DEFAULT_LENGTH_NAMES = {"size", "bytesize", "length", "len", "count", "cap"}

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    visitor = Visitor.new(source, config.strings("length_names", DEFAULT_LENGTH_NAMES.to_a))
    source.ast.try &.accept(visitor)
    visitor.issues
  end
end

Awesome::Guard.registered << Awesome::Guards::SliceAsCString
