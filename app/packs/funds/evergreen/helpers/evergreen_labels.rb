# Evergreen wording for screens, emails, documents and exports. Closed-ended code never calls this,
# so closed-ended labels are untouched.
#
# A word is resolved, first match wins:
#   1. the fund's own unit name (evergreen_fund_settings.unit_term) — for the unit words only
#   2. the fund entity's overrides (entity_settings.evergreen_labels, e.g. {"unit" => "share"})
#   3. the locale file (config/locales/evergreen.*.yml) for the request's locale — the browser's
#      (WithLocale), APP_LOCALE only when the browser sends none. Deliberately NOT the system locale
#      that LocaleHelper#sys_t forces for KYC terms: product decision (2026-10-10) that evergreen
#      wording follows the reader's browser; a firm wanting fixed words sets them as overrides (2).
# Always pass the fund (or its entity): the wording is the GP's, also when an LP or a job renders it.
#
# Cost: an entity's overrides are read once per request / job (RequestCache) through Rails.cache,
# which EntitySetting clears when they change — so a page full of labels is hash lookups.
# Worked examples H36, C7, E212–E214 — openspec/changes/open-ended-funds/design.md#worked-examples
module EvergreenLabels
  # Per-request / per-job memo of each entity's overrides. Its own CurrentAttributes (not Current,
  # which holds only the acting user) so it gets the same reset between requests and jobs.
  class RequestCache < ActiveSupport::CurrentAttributes
    attribute :overrides
  end

  # The unit names a fund or entity may choose (default "unit")
  UNIT_TERMS = %w[unit share].freeze

  # The words an entity may override in its settings ("Open-ended fund wording"), besides the unit
  OVERRIDABLE = %w[capital_commitment capital_commitments transaction_date subscription_date redemption_date
                   contract_note redemption_advice carried early_fee].freeze

  module_function

  # EvergreenLabels.t(:capital_commitment, fund: @fund) → "Folio" / "Account" / an entity's own word.
  # Labels may use %{unit} %{units} %{Unit} %{Units}, filled with the resolved unit name.
  # lower: true for mid-sentence use — see #lower; article: true prefixes "a" / "an".
  def t(key, fund: nil, entity_id: nil, lower: false, article: false, **)
    entity_id ||= fund&.entity_id
    custom = overrides_for(entity_id)
    vars = unit_vars(fund, custom)
    text = if vars.key?(key.to_sym)
             vars[key.to_sym]
           elsif (custom_text = custom[key.to_s].presence)
             # An override is plain text, but may use the same %{unit} placeholders
             I18n.interpolate(custom_text, vars)
           else
             I18n.t("evergreen.labels.#{key}", **vars, **)
           end
    text = self.lower(text) if lower
    article ? with_article(text) : text
  end

  # Mid-sentence form: lower-cases ordinary capitalised words ("Redemption date" → "redemption date")
  # but keeps acronyms and mixed-case words an entity typed ("NAV Date" → "NAV date", "CAS" stays)
  def lower(text)
    text.to_s.gsub(/\b[A-Z][a-z]+\b/, &:downcase)
  end

  # "an exit load" / "a redemption charge" — the article follows whatever word the label resolved to
  def with_article(text)
    "#{text.to_s.match?(/\A[aeiou]/i) ? 'an' : 'a'} #{text}"
  end

  # The unit word and its forms: fund setting, then entity override, then locale
  def unit_vars(fund, custom)
    unit = fund_unit_term(fund).presence || custom["unit"].presence || I18n.t("evergreen.labels.unit")
    units = unit.pluralize
    { unit:, units:, Unit: unit.capitalize, Units: units.capitalize }
  end

  def fund_unit_term(fund)
    fund&.evergreen_fund_setting&.unit_term if fund.respond_to?(:evergreen_fund_setting)
  end

  # The entity's overrides, memoised for the request / job and cached across them
  def overrides_for(entity_id)
    return {} unless entity_id

    RequestCache.overrides ||= {}
    RequestCache.overrides[entity_id] ||= Rails.cache.fetch(cache_key(entity_id), expires_in: 1.day) do
      raw = EntitySetting.where(entity_id:).pick(:evergreen_labels)
      (raw.is_a?(String) ? JSON.parse(raw) : raw).to_h.transform_keys(&:to_s)
    end
  end

  def cache_key(entity_id)
    ["evergreen_labels", entity_id]
  end

  # "Subscription settlement — 2 Nov 2026" (built with I18n.l, never strftime)
  def settlement_name(kind, date)
    "#{t(kind.to_s == 'subscription' ? :capital_call : :distribution)} — #{I18n.l(date, format: :abbr_month_day_year, locale: :en)}"
  end
end
