# DeepInheritance — inheritance used instead of composition.
# The bad snippet for `awesome doc` and examples/awful; one issue:
# Gamma sits three levels deep (two visible hops between project
# classes). The bases are abstract and share an abstract `run` with
# Gamma, so the sibling code guards (SingleSubclass, Subclass-
# NoOverride) legitimately stay quiet on this hierarchy.
# Self-sufficient in one file — the project index treats it as a
# one-file project.

abstract class Alpha
  abstract def run
end

abstract class Beta < Alpha; end

class Gamma < Beta
  def run; end
end
