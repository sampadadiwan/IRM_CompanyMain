# Dealing list / workspace helpers. Worked examples H16, H17
module EvergreenDealingHelper
  STEP_ORDER = [
    ["Collect subscription money", :money_collected_before?, ->(dd, p) { dd.pre_funded? && p.subscriptions? }],
    ["Approve NAV", :nav_approved?, ->(_dd, _p) { true }],
    ["Review and confirm dealing", :confirmed?, ->(_dd, _p) { true }],
    ["Allot units", :units_allotted?, ->(_dd, p) { p.subscriptions? }],
    ["Pay redemptions", :redemptions_paid?, ->(_dd, p) { p.redemptions? }],
    ["Cancel units", :units_cancelled?, ->(_dd, p) { p.redemptions? }],
    ["Generate documents", :documents_generated?, ->(dd, _p) { EvergreenDealingDocuments.templates?(dd.fund) }],
    ["Approve and send documents", :documents_sent?, ->(dd, _p) { EvergreenDealingDocuments.templates?(dd.fund) }],
    ["Close dealing date", :closed?, ->(_dd, _p) { true }]
  ].freeze

  # The current step's name for the list: "Open for orders" before anything is ordered, ✓ Closed at the end
  def evergreen_dealing_step(dealing_date)
    return "✓ Closed" if dealing_date.closed?

    progress = DealingProgress.new(dealing_date)
    return "○ Open for orders" if dealing_date.open? && !progress.subscriptions? && !progress.redemptions?

    # F5: before the last deadline the date is still taking orders — the NAV and the review come after it.
    # Only a pre-funded date's unpaid subscriptions are work to do now (money must arrive by the cut-off)
    if dealing_date.open? && !dealing_date.deadlines_passed?
      collecting = dealing_date.pre_funded? && progress.subscriptions? && !progress.money_collected_before?
      return collecting ? "● Collect subscription money" : "● Open for orders"
    end

    current = STEP_ORDER.find { |_, check, applies| applies.call(dealing_date, progress) && !progress.public_send(check) }
    current ? "● #{current.first}" : "● Close dealing date"
  end

  # The confirm popup's action-summary cards (same layout as the app's "Immediate Actions" popups):
  # allot, pay, carry — kept to three short cards. Worked example H21
  def evergreen_confirm_summary(pricing, fund)
    units = pricing.subscriptions.sum(&:units)
    paid = pricing.redemptions.select { |r| r.filled_units.positive? }
    carried = pricing.redemptions.select { |r| r.carried_units.positive? }
    carried_value = carried.sum { |r| r.requested_value_cents - r.value_cents }
    unit_word = EvergreenLabels.t(:units, fund:)
    cards = []
    cards << ["green", "ti-coins", EvergreenLabels.t(:allocate_units, fund:), "#{number_with_precision(units, precision: 4, delimiter: ',')} #{unit_word} to #{pluralize(pricing.subscriptions.size, 'investor')}"] if pricing.subscriptions.any?
    cards << ["blue", "ti-cash", "Pay redemptions", "#{pluralize(paid.size, 'redemption')} — #{evergreen_money(paid.sum(&:value_cents), fund)}"] if paid.any?
    cards << ["amber", "ti-clock", "Carry forward", "#{evergreen_money(carried_value, fund)} with #{pluralize(carried.size, 'gate notice')}"] if carried.any?
    # Orders not ready: rolled or cancelled, as each row's fate says (E108, E181)
    cards << ["grey", "ti-arrow-forward", "Not ready", "#{pluralize(pricing.unready.size, 'order')} rolled or cancelled — see the list"] if pricing.unready.any?
    evergreen_action_summary(cards)
  end

  # Approve & send popup: the same action-summary cards as Confirm (§ Dealing-date documents).
  # fund: whose document names to use ("contract note" / "trade confirmation")
  def evergreen_documents_summary(notes, advices, fund: @fund)
    cards = []
    note = EvergreenLabels.lower(EvergreenLabels.t(:contract_note, fund:))
    advice = EvergreenLabels.lower(EvergreenLabels.t(:redemption_advice, fund:))
    kinds = [(pluralize(notes, note) if notes.positive?), (pluralize(advices, advice) if advices.positive?)].compact
    cards << ["green", "ti-file-check", "Approve", kinds.join(" and ")]
    cards << ["blue", "ti-mail", "Email investors", "Each investor gets their document attached"]
    cards << ["grey", "ti-lock", "Final", "Approved documents can no longer be regenerated"]
    evergreen_action_summary(cards)
  end

  # The shared "Immediate Actions" popup body (app/assets/stylesheets/custom/action_summary_modal.scss,
  # the KYC Request Updates layout): an intro bar, then one tinted card per effect.
  # cards: [[tint, icon, title, line], …] — tint is one the stylesheet defines (blue, amber, green,
  # purple, red, grey); any other name renders an untinted card with a bare icon
  def evergreen_action_summary(cards, action: "Proceed")
    intro = tag.div(class: "action-summary__intro") do
      tag.div("Immediate Actions", class: "fw-bold text-dark") +
        tag.div(safe_join(["The following will happen when you click ", tag.strong(action), ":"]), class: "text-muted")
    end
    items = cards.map do |tint, icon, title, desc|
      tag.div(class: "action-summary__item action-summary__item--#{tint}") do
        tag.span(tag.i(class: "ti #{icon}"), class: "action-summary__icon") +
          tag.div(tag.div(title, class: "action-summary__title") + tag.div(desc, class: "action-summary__desc"))
      end
    end
    intro + tag.div(safe_join(items), class: "action-summary__list")
  end

  # An order's status timeline for the investor's Requests tab (proposal LP-2), in the GP's words
  # ("Part-filled", the fund's word for "carried"). One step per line. Worked example H38
  def evergreen_request_timeline(order)
    fund = order.fund
    steps = ["✓ Received #{l(order.received_at.to_date, format: :short)}"]
    # Use the preloaded fills when the page loaded them (Requests tab), else query
    fills = (order.dealing_fills.loaded? ? order.dealing_fills.to_a : order.dealing_fills.includes(:dealing_date, :fund_nav, :capital_distribution_payment).to_a).sort_by(&:id)
    if order.subscription?
      steps.concat(eg_subscription_timeline_steps(order, fills, fund))
    else
      steps.concat(eg_redemption_timeline_steps(order, fills, fund))
    end
    steps << "Cancelled" if order.status == "cancelled"
    safe_join(steps.map { |s| tag.div(s) })
  end

  # Subscription: money in (dated the payment), then the units allotted at the NAV they were priced at
  def eg_subscription_timeline_steps(order, fills, fund)
    steps = []
    steps << "Subscription reduced to #{evergreen_money(order.amount_cents, fund)} (received)" if order.amount_reduced?
    if order.fully_paid?
      rem = order.capital_remittance
      # The recorded payment date; updated_at only when no payment date was recorded
      steps << "✓ Money in #{l(rem.payment_date || rem.updated_at.to_date, format: :short)}"
    end
    allotted = fills.select(&:fund_unit_id)
    if allotted.any?
      allotted.each do |f|
        nav = f.fund_nav ? " (NAV of #{l(f.fund_nav.nav_date, format: :short)})" : ""
        steps << "✓ #{eg_units(f.units, fund:)} allotted at #{evergreen_money(f.nav_per_unit_cents, fund)}#{nav}"
      end
    else
      steps << "○ #{EvergreenLabels.t(:Units, fund:)} allotted"
    end
    steps
  end

  # Redemption: each fill — "to be paid" until its payment is marked completed, then "paid" — and
  # the queue place with what was carried while the order is still open
  def eg_redemption_timeline_steps(order, fills, fund)
    steps = []
    fills.select { |f| f.units.positive? }.each do |f|
      label = f.carried_units.to_d.positive? ? "Part-filled" : "Filled"
      paid = f.capital_distribution_payment&.completed
      steps << "#{paid ? '✓' : '●'} #{label} #{l(f.dealing_date.date, format: :short)} — #{eg_units(f.units, fund:)} #{paid ? 'paid' : 'to be paid'}"
    end
    if order.open? && (pos = order.queue_position)
      carried = fills.last&.carried_units
      carried_word = EvergreenLabels.t(:carried, fund:, lower: true)
      steps << "● Queued ##{pos} for #{l(order.dealing_date.date, format: :short)}#{" — #{eg_units(carried, fund:)} #{carried_word}" if carried&.positive?}"
    end
    steps
  end

  # Review fix 8: " · ₹40,00,000 used earlier this quarter" on a gate card, when earlier dealing dates in the
  # same gate period already paid redemptions — so the card's amount reads as what is LEFT
  def eg_gate_used_note(used_cents, fund)
    return "" unless used_cents.to_d.positive?

    period = { "quarter" => "this quarter", "year" => "this year" }.fetch(fund.evergreen_fund_setting.gate_period, "this period")
    " · #{evergreen_money(used_cents, fund)} used earlier #{period}"
  end
end
