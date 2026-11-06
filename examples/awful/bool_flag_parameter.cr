# BoolFlagParameter — two behaviours hiding behind one name.
# The bad snippet for `awesome doc` and examples/awful; two issues:
# both Bool params are fed literal true and false at call sites.

class Sync
  def run(force : Bool) # one name, two behaviours
  end
end

Sync.new.run(true)  # the branch callers actually take,
Sync.new.run(false) # spelled out at every call site

class Job
  def retries(exhausted : Bool)
  end
end

Job.new.retries(exhausted: true)
Job.new.retries(exhausted: false)
