# ToSWithoutIo — io << obj and "#{obj}" never see these overrides.
def to_s
  "x=#{@x}"
end

struct Money
  def to_s : String # return type doesn't fix the hook
    "#{@cents / 100}"
  end
end
