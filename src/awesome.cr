# The compiler's own syntax tools (parser, AST, visitor) — shipped with
# every Crystal install, so guards work on the exact AST the compiler
# sees. No external dependency.
require "compiler/crystal/syntax/*"
require "./awesome/*"
require "./awesome/guards/*"
