# KeeperScanner for ToUnsafeEscape — see guards/to_unsafe_escape.cr.
# Names of variables that are stored into an ivar/class var/constant
# anywhere in the file (`@keep = @blob`, `KEEP = blob`): their owner
# is reachable for as long as that field lives, so a to_unsafe
# pointer taken from them stays valid. File-granular on purpose —
# generous suppression beats false positives on a crash guard.
class Awesome::Guards::ToUnsafeEscape::KeeperScanner < Crystal::Visitor
  getter kept = Set(String).new

  def visit(node : Crystal::Assign)
    if node.target.is_a?(Crystal::InstanceVar | Crystal::ClassVar | Crystal::Path) &&
       (value = node.value).is_a?(Crystal::Var | Crystal::InstanceVar)
      @kept << value.to_s
    end
    true
  end

  def visit(node : Crystal::ASTNode)
    true
  end
end
