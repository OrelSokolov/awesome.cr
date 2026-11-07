# Guard defined for the per-project pass spec only: a probe recording
# its per-project call. The spec registers it only around the
# assertions that need it and unregisters in ensure, so the rest of the
# suite never sees it.
class ProjectProbeGuard < Awesome::Guard
  KIND = "code"
  class_property calls = [] of Array(String)

  def test_project(sources : Array(Awesome::Source), config : Awesome::GuardConfig) : Array(Awesome::Issue)
    @@calls << sources.map(&.path)
    [] of Awesome::Issue
  end
end
