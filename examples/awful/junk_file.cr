# JunkFile — a file stuffed with types instead of one type per file.
# The bad snippet for `awesome doc` and examples/awful; two issues:
# User and Order make the file a junk file (one class per file), and
# Shop nests two modules (at most one nested module per module).
# One class with a single nested class would stay quiet.

class User
  def initialize(@name : String)
  end
end

class Order
  def initialize(@user : User)
  end
end

module Shop
  module Catalog
  end

  module Billing
  end
end
