# SingleSubclass — inheritance "for the future" that never came.
# The bad snippet for `awesome doc` and examples/awful; one issue:
# FlatFile is Storage's only subclass. Self-sufficient in one file —
# the project index treats it as a one-file project.

class Storage
  def save(data); end
end

class FlatFile < Storage
  def save(data); end
end
