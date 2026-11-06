require "./spec_helper"

describe Awesome::Guards::LogEagerInterp do
  it "flags an eager interpolated log message" do
    issues = guard_issues(Awesome::Guards::LogEagerInterp, <<-CODE)
      log.info "x=\#{x}"
    CODE
    issues.size.should eq(1)
    issues[0].line.should eq(1)
    issues[0].message.should contain("{")
  end

  it "flags every level and the logger name" do
    issues = guard_issues(Awesome::Guards::LogEagerInterp, <<-CODE)
      log.trace "a\#{a}"
      log.debug "a\#{a}"
      log.warn "a\#{a}"
      log.error "a\#{a}"
      log.fatal "a\#{a}"
      logger.notice "a\#{a}"
    CODE
    issues.size.should eq(6)
  end

  it "flags an instance-var logger" do
    issues = guard_issues(Awesome::Guards::LogEagerInterp, <<-CODE)
      @log.info "x=\#{x}"
    CODE
    issues.size.should eq(1)
  end

  it "does not flag the lazy block form" do
    guard_issues(Awesome::Guards::LogEagerInterp, <<-CODE).should be_empty
      log.info { "x=\#{x}" }
    CODE
  end

  it "does not flag literal-only messages" do
    guard_issues(Awesome::Guards::LogEagerInterp, <<-CODE).should be_empty
      log.info "started"
    CODE
  end

  it "does not flag other receivers" do
    guard_issues(Awesome::Guards::LogEagerInterp, <<-CODE).should be_empty
      telemetry.info "x=\#{x}"
      Log.info "x=\#{x}"
    CODE
  end
end
