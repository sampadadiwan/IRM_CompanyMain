# Labels, tooltips and preset summaries for the evergreen settings wizard.
# Tooltip text is taken from how the services use each field (cut-off and notice: DealingCalendar;
# minimums and lock-up: OrderEligibility; gates: GateAllocator / DealingPricer; NAV lines: FundNavBuilder).
module EvergreenSettingsHelper
  # The evergreen wizard's steps (icon, title), in order: Evergreen Settings shows them all; New Fund
  # shows them after its own two steps for an open-ended fund (evergreen-fund-on-create ①②)
  # The calendar step is named with the fund's word for its dealing dates ("Dealing dates" / "Transaction dates")
  def eg_wizard_steps(fund = @fund)
    [["building-bank", "Preset"], ["calendar", eg_calendar_title(fund)], ["cash", "Subscriptions"],
     ["door-exit", "Redemptions"], ["filter", "Gates"], ["layers-subtract", "Classes"],
     ["route", "Journeys & NAV"], ["bell", "Notifications"], ["checklist", "Review"]]
  end

  # Title of the calendar step, in the fund's wording
  def eg_calendar_title(fund = @fund)
    EvergreenLabels.t(:transaction_date, fund:).pluralize
  end

  # The fund's currency symbol for tooltip examples (₹, $ …); the code itself when Money doesn't know it,
  # and nothing on a New Fund form before a currency is chosen
  def eg_currency_symbol(fund)
    code = fund&.currency
    return "" if code.blank?

    Money::Currency.find(code)&.symbol || code
  end

  # Small ⓘ icon with a Bootstrap tooltip (initialised by the tooltip controller on the wizard)
  def eg_tip(text)
    tag.i("", class: "ti ti-info-circle text-muted ms-1", tabindex: 0, role: "img", 'aria-label': text,
              data: { bs_toggle: "tooltip", bs_placement: "top", bs_title: text })
  end

  # A form label with an optional icon and a tooltip
  # required: a red * — the field can't be left blank (most come pre-filled with a default)
  def eg_label(form, field, text, tip, icon: nil, required: false)
    form.label(field, class: "form-label fw-semibold") do
      safe_join([(tag.i("", class: "ti ti-#{icon} me-1 text-info") if icon), text,
                 (eg_required if required), eg_tip(tip)].compact)
    end
  end

  def eg_required
    tag.span("*", class: "text-danger ms-1", title: "Required", 'aria-label': "required")
  end

  # Step heading: icon in a soft circle, title with a "Step n of N" badge, and one line saying what the
  # step controls (evergreen-fund-on-create: wizard look)
  def eg_step_intro(icon, title, text, step: nil, total: nil)
    badge = tag.span("Step #{step} of #{total}", class: "badge bg-info-subtle text-info ms-2 align-middle") if step && total
    tag.div(class: "d-flex align-items-start gap-3 mb-4 p-3 rounded border bg-light") do
      safe_join([tag.span(tag.i("", class: "ti ti-#{icon} fs-5 text-info"),
                          class: "d-inline-flex align-items-center justify-content-center rounded-circle bg-info-subtle",
                          style: "width: 2.5rem; height: 2.5rem; flex: 0 0 2.5rem;"),
                 tag.div { safe_join([tag.h5(safe_join([title, badge].compact), class: "mb-1"), tag.small(text, class: "text-muted")]) }])
    end
  end

  # A section heading inside a step: icon, title and an optional one-line hint, over a hairline, so a
  # step reads as a few short groups instead of one long grid
  def eg_section(icon, title, hint = nil)
    tag.div(class: "d-flex align-items-baseline gap-2 border-bottom pb-1 mb-3 mt-2") do
      safe_join([tag.h6(safe_join([tag.i("", class: "ti ti-#{icon} me-1 text-info"), title]), class: "mb-0 fw-semibold"),
                 (tag.small(hint, class: "text-muted") if hint)].compact)
    end
  end

  # A number field with its unit beside it (%, days, months, a currency), so the value reads plainly
  def eg_number(form, field, unit, prefix: false, **)
    addon = tag.span(unit, class: "input-group-text")
    input = form.number_field(field, class: "form-control", **)
    tag.div(safe_join(prefix ? [addon, input] : [input, addon]), class: "input-group")
  end

  # What choosing a preset changes, and what it leaves as set — shown on the Preset step so people
  # know before they pick (config/evergreen_presets.yml keys)
  EG_PRESET_EFFECTS = [
    ["calendar", "%{calendar}", "Subscription and redemption calendars", "%{dealing_day}"],
    ["cash", "Subscriptions", "Payment timing", "Cut-off, days to pay, minimums, payment instructions"],
    ["door-exit", "Redemptions", "Notice, lock-up and its type, %{early_fee}", "Ways to redeem, settlement days, minimum holding"],
    ["filter", "Gates", "Gate %, level and period, who is paid first, per-investor cap", nil],
    ["layers-subtract", "Classes", nil, "Starting prices and class overrides"],
    ["route", "Journeys & NAV", "Per-order journeys", "NAV ledger names"],
    ["bell", "Notifications", nil, "Every switch and number"]
  ].freeze

  # EG_PRESET_EFFECTS with the fund's wording filled in — at render time, not load time, so the locale
  # and the entity's own wording apply (%{early_fee}, %{calendar}, %{dealing_day})
  def eg_preset_effects(fund)
    words = { "%{early_fee}" => EvergreenLabels.lower(EvergreenLabels.t(:early_fee, fund:)),
              "%{calendar}" => eg_calendar_title(fund), "%{dealing_day}" => eg_dealing_day_label(fund) }
    EG_PRESET_EFFECTS.map { |row| row.map { |cell| cell&.gsub(/%\{\w+\}/) { |k| words.fetch(k, k) } } }
  end

  # Label of the dealing_day field: where in each period the dealing date falls
  def eg_dealing_day_label(fund = @fund)
    "#{EvergreenLabels.t(:transaction_date, fund:)} falls on"
  end

  # One-line, plain-English summary of a preset's values (config/evergreen_presets.yml)
  def eg_preset_summary(values)
    eg_preset_points(values).join(" · ")
  end

  # The preset's terms as short points, shown as a list on its card (evergreen-fund-on-create ②)
  def eg_preset_points(values)
    v = values.to_h.stringify_keys
    parts = []
    parts << "#{v['subscription_calendar'].to_s.humanize} subscriptions, #{v['redemption_calendar'].to_s.humanize.downcase} redemptions" if v["subscription_calendar"]
    parts << (v["payment_timing"] == "after" ? "pay after dealing" : "pay before dealing") if v["payment_timing"]
    parts << "#{v['notice_days']}-day notice" if v["notice_days"]
    if v["lock_up_months"].to_i.positive?
      fee = v.dig("early_redemption_fee", "pct")
      parts << "#{v['lock_up_months']}-month #{v['lock_up_type']} lock-up#{" (#{fee}% #{EvergreenLabels.lower(EvergreenLabels.t(:early_fee, fund: @fund))})" if fee && v['lock_up_type'] == 'soft'}"
    end
    parts << (if v["gate_pct"].to_d.positive?
                "#{v['gate_pct']}% #{v['gate_method'] == 'fifo' ? 'FIFO' : 'pro-rata'} gate per #{v['gate_period'].to_s.humanize.downcase}"
              else
                "no gate"
              end)
    parts << { "off" => "no order journeys", "subscriptions" => "journeys for subscriptions", "both" => "journeys for all orders" }[v["order_journeys"]] if v["order_journeys"]
    parts
  end

  # A plain icon per typical setup, for its card
  EG_PRESET_ICONS = { "cat_iii_aif" => "building-bank", "us_tender_offer" => "flag", "us_interval_fund" => "calendar-repeat",
                      "hedge_fund_style" => "chart-line" }.freeze

  def eg_preset_icon(key)
    EG_PRESET_ICONS.fetch(key.to_s, "template")
  end
end
