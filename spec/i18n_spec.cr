require "./spec_helper"
require "file_utils"

describe Awesome::I18n do
  it "embeds both locales into the binary" do
    Awesome::I18n::EMBEDDED_CATALOGS["en"]?.should_not be_nil
    Awesome::I18n::EMBEDDED_CATALOGS["ru"]?.not_nil!.should contain("guards.")
    Awesome::I18n.catalog("en").should_not be_empty
    Awesome::I18n.catalog("ru").should_not be_empty
    Awesome::I18n.catalog("xx").should be_empty
  end

  it "keeps base keys in sync between en and ru" do
    strip_plural = ->(keys : Array(String)) { keys.map { |k| k.split('.')[0...-1].join('.') }.uniq }
    # Base keys ("x.y") and plural bases ("x.y.one" → "x.y") must match;
    # only the plural form suffixes differ (one/other vs one/few/many).
    strip_plural.call(Awesome::I18n.catalog("en").keys.sort)
      .should eq(strip_plural.call(Awesome::I18n.catalog("ru").keys.sort))
  end

  it "interpolates named placeholders" do
    Awesome::I18n.locale = "en"
    Awesome::I18n.t("source.skipping", path: "a.cr", message: "boom")
      .should eq("skipping a.cr: boom")
  end

  it "falls back to en, then to the key itself" do
    Awesome::I18n.catalog("en")["report.awesome"].should_not be_nil
    # ru misses nothing today, but the chain must hold: delete-free check
    # via a locale with an empty catalog.
    Awesome::I18n.locale = "xx"
    Awesome::I18n.t("report.awesome").should eq("Your code is awesome.")
    Awesome::I18n.t("no.such.key").should eq("no.such.key")
  end

  it "pluralizes English with one/other" do
    Awesome::I18n.locale = "en"
    Awesome::I18n.t("report.issues", count: 1).should eq("1 issue")
    Awesome::I18n.t("report.issues", count: 3).should eq("3 issues")
  end

  it "pluralizes Russian with one/few/many" do
    Awesome::I18n.locale = "ru"
    Awesome::I18n.t("report.issues", count: 1).should eq("1 проблема")
    Awesome::I18n.t("report.issues", count: 3).should eq("3 проблемы")
    Awesome::I18n.t("report.issues", count: 5).should eq("5 проблем")
    Awesome::I18n.t("report.issues", count: 11).should eq("11 проблем")
    Awesome::I18n.t("report.issues", count: 21).should eq("21 проблема")
    Awesome::I18n.t("report.issues", count: 0).should eq("0 проблем")
  end

  it "detects the locale from the environment" do
    ENV["LC_ALL"] = "ru_RU.UTF-8"
    Awesome::I18n.from_env.should eq("ru")
    ENV["LC_ALL"] = nil
    ENV["LANG"] = "en_US.UTF-8"
    Awesome::I18n.from_env.should eq("en")
    ENV["LANG"] = "en_US.UTF-8" # restore the pinned spec env
    Awesome::I18n.resolve("ru").should eq("ru")
    Awesome::I18n.resolve(nil).should eq("en")
  end

  it "reads lang from awesome.yml" do
    Awesome::Config.from_yaml("lang: ru\n").lang.should eq("ru")
    Awesome::Config.new.lang.should be_nil
  end
end

# The safety net: every guard message must resolve in every shipped
# locale — no raw keys (missing translation) and no leftover %{…}
# placeholders (missing named argument), across the whole awful corpus.
describe "guard messages in both locales" do
  ["en", "ru"].each do |lang|
    it "resolves every message in #{lang}" do
      Awesome::I18n.locale = lang
      report = Awesome::Runner.new(Awesome::Config.new).run(["examples/awful"])
      report.issues.should_not be_empty
      report.issues.each do |issue|
        issue.message.should_not start_with("guards.")
        issue.message.should_not start_with("cli.")
        issue.message.should_not contain("%{")
      end
    end
  end
end

describe Awesome::CLI do
  it "runs with --lang ru (message content is covered by the corpus spec)" do
    dir = File.join(Dir.tempdir, "awesome_i18n_#{Random.new.hex(6)}")
    Dir.mkdir_p(dir)
    File.write(File.join(dir, "bad.cr"), "words = lines.map(&.split).flatten\n")
    Awesome::CLI.run(["--lang", "ru", dir]).should eq(1)
    Awesome::I18n.locale.should eq("ru")
  ensure
    FileUtils.rm_rf(dir) if dir
  end

  it "rejects an unknown --lang" do
    Awesome::CLI.run(["--lang", "xx"]).should eq(2)
  end
end
