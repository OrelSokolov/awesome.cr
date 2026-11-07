require "yaml"

# i18n for user-facing messages: guard issue messages, report summary,
# CLI strings. The locale catalogs (`locales/*.yml` in the repo root)
# are embedded into the binary at compile time via `read_file` — no
# runtime file lookups, the binary is self-contained (zero deps, the
# YAML is parsed once per locale and memoized).
#
#   Awesome::I18n.locale = "ru"
#   Awesome::I18n.t("guards.MapFlatten.main", call: "xs.map { … }.flatten")
#
# Message templates use %{name} placeholders. A `count:` argument
# switches the key to plural forms — subkeys `<key>.one`, `<key>.few`,
# `<key>.many`, `<key>.other` (which of them apply depends on the
# locale: English uses one/other, Russian one/few/many):
#
#   "report.issues.one": "%{count} issue"
#   "report.issues.other": "%{count} issues"
#   Awesome::I18n.t("report.issues", count: 3) # => "3 issues"
#
# Fallback chain: current locale → en → the key itself, so a missing
# translation renders the key instead of crashing.
module Awesome::I18n
  LOCALES        = {"en", "ru"}
  DEFAULT_LOCALE = "en"

  # The catalogs, read at compile time from the source tree — this is
  # what "embedded in the binary" means: no files are opened at runtime.
  EMBEDDED_CATALOGS = {
    "en" => {{ read_file("#{__DIR__}/../../locales/en.yml") }},
    "ru" => {{ read_file("#{__DIR__}/../../locales/ru.yml") }},
  }

  @@locale : String? = nil
  @@catalogs = {} of String => Hash(String, String)

  def self.locale : String
    @@locale ||= DEFAULT_LOCALE
  end

  def self.locale=(lang : String)
    @@locale = lang
  end

  # Locale from the environment (LC_ALL beats LANG): anything starting
  # with "ru" maps to ru, everything else falls back to en.
  def self.from_env : String
    lang = ENV["LC_ALL"]? || ENV["LANG"]? || ""
    lang.starts_with?("ru") ? "ru" : "en"
  end

  # Resolves an explicit override (CLI flag, awesome.yml `lang:`) with
  # the environment fallback behind it.
  def self.resolve(override : String? = nil) : String
    override || from_env
  end

  # Parsed catalog of a locale (flat dotted keys → templates), parsed
  # lazily and memoized. Unknown locales give an empty catalog, which
  # makes every lookup fall back to en.
  def self.catalog(lang : String) : Hash(String, String)
    @@catalogs[lang] ||= parse_catalog(EMBEDDED_CATALOGS[lang]?)
  end

  private def self.parse_catalog(raw : String?) : Hash(String, String)
    parsed = {} of String => String
    return parsed unless raw
    YAML.parse(raw).as_h.each { |k, v| parsed[k.to_s] = v.to_s }
    parsed
  rescue YAML::ParseException
    {} of String => String
  end

  def self.t(key : String, **args) : String
    count = args[:count]?
    template = count.is_a?(Int) ? plural_template(key, count) : lookup(key)
    interpolate(template, args)
  end

  def self.lookup(key : String) : String
    catalog(locale)[key]? || catalog(DEFAULT_LOCALE)[key]? || key
  end

  # Picks the plural subkey for a count: the locale's own form first,
  # then the English form, then the bare key, then the key itself.
  private def self.plural_template(key : String, count) : String
    {plural_form(locale, count), plural_form(DEFAULT_LOCALE, count)}.each do |form|
      template = catalog(locale)["#{key}.#{form}"]? || catalog(DEFAULT_LOCALE)["#{key}.#{form}"]?
      return template if template
    end
    catalog(locale)[key]? || catalog(DEFAULT_LOCALE)[key]? || key
  end

  # Russian plural rules: 1/…21 проблема (one), 2–4/…22–24 проблемы
  # (few), everything else including 0 and 11–14 — проблем (many).
  # English: 1 issue (one), otherwise issues (other).
  private def self.plural_form(lang : String, count) : String
    case lang
    when "ru"
      if count % 10 == 1 && count % 100 != 11
        "one"
      elsif (2..4).includes?(count % 10) && !(12..14).includes?(count % 100)
        "few"
      else
        "many"
      end
    else
      count == 1 ? "one" : "other"
    end
  end

  private def self.interpolate(template : String, args : NamedTuple) : String
    template.gsub(/%\{(\w+)\}/) do
      args[$1]?.try(&.to_s) || ""
    end
  end
end
