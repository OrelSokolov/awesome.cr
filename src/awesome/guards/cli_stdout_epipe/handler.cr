# Handler for CliStdoutEpipe — see guards/cli_stdout_epipe.cr.
#
# Does the file handle EPIPE anywhere: a `rescue` clause naming
# IO::Error (types are Path/Generic nodes, compared as written), or a
# constant reference to Errno::EPIPE / Signal::PIPE.
class Awesome::Guards::CliStdoutEpipe::Handler < Crystal::Visitor
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
