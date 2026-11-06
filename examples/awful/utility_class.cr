# UtilityClass — a namespace pretending to be a class.
# The bad snippet for `awesome doc` and examples/awful; two issues:
# both classes hold only class methods — modules in disguise.

class Registry
  def self.load(path)
  end

  def self.save(path, data)
  end
end

class Migrations
  def self.pending
  end

  def self.run
  end
end
