# Status badges for the evergreen tabs and detail pages: soft-coloured pill + Tabler icon + tooltip, the
# same markup as AllocationRunTemplatesHelper#art_status_badge, so a status looks the same everywhere.
# Tooltip texts follow how the services treat each state (DealingPricer, OrderEligibility, FundNavReopen…).
module EvergreenBadgesHelper
  # Theme colours only (success / info / danger / secondary): blue and teal are informational, amber is
  # "needs someone to act" (soft danger) — so amber is kept for states that wait on a person
  SOFT = {
    blue: "bg-info-subtle text-info", green: "bg-success-subtle text-success", amber: "bg-danger-subtle text-danger",
    red: "bg-danger-subtle text-danger", grey: "bg-secondary-subtle text-secondary", teal: "bg-info-subtle text-info"
  }.freeze

  # The fund's evergreen wording ("units" / "shares", "Folio" / "Account") — see EvergreenLabels
  def eg_word(key, fund)
    EvergreenLabels.t(key, fund:)
  end

  def eg_badge(color, icon, label, tip = nil, id: nil, extra: nil)
    content_tag(:span, class: "badge #{SOFT.fetch(color)} fw-normal #{extra}", id:, title: tip.presence, data: (tip.present? ? { bs_toggle: "tooltip" } : {})) do
      safe_join([content_tag(:i, "", class: "ti ti-#{icon} me-1"), label])
    end
  end

  # ---- Dealing dates ----
  DEALING_STEP_BADGE = {
    "Open for orders" => [:blue, "calendar", "Orders are being received for this date."],
    "Collect subscription money" => [:blue, "cash", "Pre-funded: subscriptions not paid by the cut-off roll or are cancelled at confirmation."],
    "Approve NAV" => [:blue, "hourglass", "Confirm stays disabled until the NAV for this dealing date is approved by a user with the approver role."],
    "Review and confirm dealing" => [:green, "circle-check", "Ready: open the date, review the pricing and confirm."],
    "Allot units" => [:teal, "coins", "Units are allotted as subscription money is verified."],
    "Pay redemptions" => [:teal, "cash-banknote", "Mark each redemption paid from its row on the Redemptions tab; its units are then cancelled."],
    "Cancel units" => [:teal, "receipt", "Units are cancelled when each redemption is marked paid."],
    "Generate documents" => [:blue, "file-text", "Click Generate documents to build contract notes and advices from the fund's templates."],
    "Approve and send documents" => [:blue, "file-check", "Review the generated documents, then Approve & send to email them to investors."],
    "Close dealing date" => [:grey, "archive", "Everything has settled — close the date."],
    "Closed" => [:grey, "archive", "Settled and closed."]
  }.freeze

  def eg_dealing_step_badge(dealing_date)
    step = evergreen_dealing_step(dealing_date)
    label = step.sub(/\A[○●✓] /, "")
    color, icon, tip = DEALING_STEP_BADGE.fetch(label, [:grey, "point", nil])
    # The step names above are lookup keys; the badge shows them in the fund's wording
    eg_badge(color, icon, eg_step_text(label, dealing_date.fund), eg_step_text(tip, dealing_date.fund))
  end

  # A dealing step's name or tooltip with the fund's words for units, documents and the dealing date
  def eg_step_text(text, fund)
    return text if text.nil?

    case text
    when "Allot units" then eg_word(:allocate_units, fund)
    when "Cancel units" then eg_word(:redeem_units, fund)
    when "Close dealing date" then "Close #{EvergreenLabels.lower(eg_word(:transaction_date, fund))}"
    else
      text.sub("this dealing date", "this #{EvergreenLabels.lower(eg_word(:transaction_date, fund))}")
          .sub("contract notes and advices",
               "#{EvergreenLabels.lower(eg_word(:contract_note, fund)).pluralize} and #{EvergreenLabels.lower(eg_word(:redemption_advice, fund)).pluralize}")
          .sub(/\AUnits are/, "#{eg_word(:Units, fund)} are").sub("; its units are", "; its #{eg_word(:units, fund)} are")
    end
  end

  # Red once the cut-off has passed for an open date; amber in the last three days
  def eg_cutoff_badge(dealing_date)
    return unless dealing_date.open?

    days = (dealing_date.cutoff_at.to_date - Time.zone.today).to_i
    if days.negative?
      eg_badge(:red, "clock-x", "Passed", "New subscriptions now go to the following #{EvergreenLabels.lower(eg_word(:subscription_date, dealing_date.fund))}.")
    elsif days <= 3
      eg_badge(:blue, "clock", days.zero? ? "Today" : "In #{days}d", "Last day to subscribe for this #{EvergreenLabels.lower(eg_word(:subscription_date, dealing_date.fund))}: #{l(dealing_date.cutoff_at.to_date)}.")
    end
  end

  # ---- Orders ----
  def eg_order_kind_badge(order)
    fund = order.fund
    units = eg_word(:units, fund)
    nav = eg_word(:nav_per_unit, fund)
    if order.subscription?
      eg_badge(:green, "login", eg_word(:subscription, fund), "Buys #{units} at the #{EvergreenLabels.lower(eg_word(:subscription_date, fund))}'s #{nav}.")
    else
      eg_badge(:blue, "logout", eg_word(:redemption, fund), "Sells #{units} back at the #{EvergreenLabels.lower(eg_word(:redemption_date, fund))}'s #{nav}, subject to the gate.")
    end
  end

  # How the order arrived: portal (investor), admin entry or upload
  def eg_order_source_icon(order)
    icon, tip = case order.source
                when "portal" then ["world", "Placed by the investor on the portal"]
                when "upload" then ["upload", "Uploaded by #{order.entered_by&.full_name || 'an admin'}"]
                else ["user", "Entered by #{order.entered_by&.full_name || 'an admin'}"]
                end
    content_tag(:i, "", class: "ti ti-#{icon} text-muted me-1", title: tip, data: { bs_toggle: "tooltip" })
  end

  def eg_order_status_badge(order)
    setting = order.fund.evergreen_fund_setting
    date_label = EvergreenLabels.lower(eg_word(order.subscription? ? :subscription_date : :redemption_date, order.fund))
    if order.subscription? && order.pending? && setting.pre_funded? && !order.fully_paid?
      return eg_badge(:amber, "cash-off", "Awaiting money", "Pre-funded: the money must arrive by #{l(order.dealing_date.cutoff_at.to_date)} or the order #{setting.unready_handling == 'cancel' ? 'is cancelled' : "rolls to the next #{date_label}"}.")
    end
    if order.pending? && setting.journeys_for?(order.kind) && (waiting = OrderJourneyStatus.waiting_on(order))
      return eg_badge(:amber, "route", "Not ready", "Waiting on: #{waiting}.")
    end

    case order.status
    when "pending" then eg_badge(:blue, "clock", "Pending", "Will be dealt on #{l(order.dealing_date.date)}.")
    when "partially_filled" then eg_badge(:teal, "chart-pie", "Part-filled", "The gate filled part of it; the rest is #{EvergreenLabels.lower(eg_word(:carried, order.fund))} to #{l(order.dealing_date.date)} at the front of the queue.")
    when "dealt" then eg_badge(:green, "check", eg_word(:dealt, order.fund), "Priced and settled through the #{date_label}.")
    when "cancelled" then eg_badge(:grey, "x", "Cancelled", order.rejected_reason.presence)
    else eg_badge(:grey, "point", order.status.humanize)
    end
  end

  def eg_queue_badge(order)
    return unless order.redemption? && order.open? && (pos = order.queue_position)

    eg_badge(:grey, "list-numbers", "##{pos}", eg_queue_tooltip(order, pos))
  end

  # Review fix 7: the tooltip follows the fund's gate — it used to say FIFO even for pro-rata funds,
  # where the order received doesn't change how much each request is paid
  def eg_queue_tooltip(order, pos)
    setting = order.fund.evergreen_fund_setting
    place = "#{pos.ordinalize} in the redemption queue for #{l(order.dealing_date.date)}"
    place += " (Class #{order.unit_type})" if setting.gate_level == "class"
    if setting.gate_pct.to_d.zero? && setting.investor_gate_pct.to_d.positive?
      "#{place} — no fund gate; each investor is capped at #{setting.investor_gate_pct.to_d.round(2).to_s.sub(/\.0+$/, '')}% of their holding per gate period."
    elsif setting.gate_pct.to_d.zero?
      "#{place} — this fund has no gate, so every request on the date is paid in full."
    elsif setting.gate_method == "fifo"
      "#{place} — the gate fills requests in this order (first received, first paid)."
    else
      "#{place} — the gate is pro-rata: every request on the date is filled by the same %, whatever its place."
    end
  end

  def eg_order_terms_badges(order)
    badges = []
    units = eg_word(:units, order.fund)
    fee = eg_word(:early_fee, order.fund)
    badges << eg_badge(:grey, "stack-2", "All #{units}", "Counted at confirmation, including #{units} allotted after the order was placed.") if order.all_units
    badges << eg_badge(:grey, "lock-open", "#{fee} #{order.early_fee_pct.to_d.round(2).to_s.sub(/\.0+$/, '')}%", "Part of these #{units} is in a soft lock-up; the #{fee.downcase} is deducted from the payment.") if order.early_fee_pct.to_d.positive?
    safe_join(badges, " ")
  end

  # ---- NAV ----
  def eg_nav_status_badge(nav)
    return eg_badge(:green, "circle-check", "Approved", "Used for dealing and shown to investors.") if nav.approved?
    return eg_badge(:red, "alert-triangle", "Stale", "The ledger or valuations changed after this draft — recalculate before approving.") if nav.stale?

    eg_badge(:blue, "pencil", "Draft", "Needs approval by a user with the approver role.")
  end

  def eg_nav_source_badge(nav)
    badges = [nav.source == "uploaded" ? eg_badge(:grey, "upload", "Uploaded", "Figures from the administrator's upload.") : eg_badge(:grey, "calculator", "Computed", "Drafted from the ledger and valuations.")]
    badges << eg_badge(:grey, "edit", "Overridden", "One or more lines were overridden with a reason — see the NAV page.") if nav.overrides_hash.present?
    badges << eg_badge(:blue, "link", "Priced #{l(nav.used_by_dealing_date.date, format: :short)}", "Used to price a #{EvergreenLabels.lower(eg_word(:transaction_date, nav.fund))}, so it cannot be reopened.") if nav.approved? && nav.used_by_dealing?
    safe_join(badges, " ")
  end

  # Change in NAV per unit against the class's previous NAV in the list
  def eg_nav_change(nav, previous)
    return unless previous&.nav_per_unit_cents.to_d.positive?

    pct = ((nav.nav_per_unit_cents.to_d / previous.nav_per_unit_cents.to_d) - 1) * 100
    up = pct >= 0
    content_tag(:small, class: up ? "text-success ms-1" : "text-danger ms-1", title: "Since #{l(previous.nav_date)}", data: { bs_toggle: "tooltip" }) do
      safe_join([content_tag(:i, "", class: "ti ti-arrow-#{up ? 'up' : 'down'}-right"), "#{pct.abs.round(2)}%"])
    end
  end

  # ---- Unit register ----
  def eg_gain_badge(gain_pct)
    return "—" unless gain_pct

    gain_pct.negative? ? eg_badge(:red, "trending-down", "#{gain_pct}%", "Value at the latest approved NAV against average cost.") : eg_badge(:green, "trending-up", "#{gain_pct}%", "Value at the latest approved NAV against average cost.")
  end

  def eg_lock_badge(row, setting)
    return "—" unless row.locked_until

    term = setting.terms_for(row.unit_type)
    units = "#{number_with_precision(row.locked_units, precision: 4, delimiter: ',')} #{eg_word(:units, setting.fund)}"
    if term.hard_lock_up?
      eg_badge(:red, "lock", l(row.locked_until), "Hard lock-up: #{units} cannot be redeemed until this date.")
    else
      eg_badge(:grey, "lock-open", l(row.locked_until), "Soft lock-up: #{units} can be redeemed before this date with the #{EvergreenLabels.lower(eg_word(:early_fee, setting.fund))}.")
    end
  end

  # fund: the page's fund (the register's rows all belong to it), so no per-row fund load
  def eg_queued_badge(row, fund: @fund)
    return unless row.queued_units.positive?

    fund ||= row.folio.fund
    eg_badge(:blue, "clock", number_with_precision(row.queued_units, precision: 4, delimiter: ",", strip_insignificant_zeros: true),
             "#{eg_word(:Units, fund)} still to redeem in open redemption orders for this #{EvergreenLabels.lower(eg_word(:capital_commitment, fund))} " \
             "(less what earlier dates filled; an amount at the latest NAV per unit).")
  end
end
