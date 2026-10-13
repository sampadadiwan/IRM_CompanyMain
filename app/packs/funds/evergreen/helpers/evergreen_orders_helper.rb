# Cells of the order book and the dealing date's Redemptions tab: the request split into an Amount and
# a Units column, and the gate's outcome for a queued redemption (EvergreenGateForecast rows) on the
# request's own row. Both screens use these cells, so a redemption reads the same on each — the list
# as a forecast, the dealing date with the figures Confirm dealing will apply.
# Worked example H34 — openspec/changes/open-ended-funds/design.md#worked-examples
module EvergreenOrdersHelper
  # Amount and Units for one order, as [amount_html, units_html]. The side the investor asked in is
  # shown plainly; the other side is an estimate at the latest approved NAV, muted with "≈". A dealt
  # order shows what it actually got on its dealing date(s) on both sides.
  def eg_order_amount_units(order, nav)
    fund = order.fund
    units_word = eg_word(:units, fund)
    # Dealt: the frozen fills are the real figures, so nothing is estimated
    if order.status == "dealt" && order.dealing_fills.any?
      return [evergreen_money(order.dealing_fills.sum { |f| f.amount_cents.to_d }, fund),
              eg_unit_count(order.dealing_fills.sum { |f| f.units.to_d })]
    end

    # Only an open order is worth estimating; a cancelled or rejected one shows just what was asked
    estimate = order.open? && nav
    tip = if nav
            "At the approved NAV of #{l(nav.nav_date)} (#{evergreen_money(nav.nav_per_unit_cents, fund)} per #{units_word.singularize}); confirming the dealing date sets the final figure."
          else
            "No approved NAV to estimate from yet."
          end
    none = order.open? ? content_tag(:span, "—", class: "text-muted", title: tip, data: { bs_toggle: "tooltip" }) : "—"
    return eg_part_filled_amount_units(order, nav, tip, none) if order.part_filled?

    case order.form
    when "amount"
      # Asked as money (every subscription, and redemptions placed as an amount)
      [evergreen_money(order.amount_cents, fund), estimate ? eg_estimate(eg_unit_count(order.amount_cents.to_d / nav.nav_per_unit_cents.to_d), tip) : none]
    when "units"
      [estimate ? eg_estimate(evergreen_money(order.units.to_d * nav.nav_per_unit_cents.to_d, fund), tip) : none, eg_unit_count(order.units)]
    else
      # All units: counted at confirmation, so today's free units are themselves an estimate
      free = order.open? ? [order.free_units, 0].max : nil
      [estimate ? eg_estimate(evergreen_money(free * nav.nav_per_unit_cents.to_d, fund), tip) : none,
       free ? eg_estimate(eg_unit_count(free), "#{units_word.capitalize} the folio holds free today; counted again at confirmation.") : none]
    end
  end

  # A linked value for fund (GP) users only; LPs see the same text, not linked (they can't open the
  # investor, folio, dealing-date or settlement pages)
  def eg_gp_link(text, path)
    gp_user? && path ? link_to(text, path, data: { turbo_frame: "_top" }) : text
  end

  # An order's investor and folio cells in the dealing-date tables (preview and confirmed): linked for fund
  # users (eg_gp_link), "New" while a first subscription has no folio yet
  def eg_investor_cell(order)
    eg_gp_link(order.investor.investor_name, investor_path(order.investor))
  end

  def eg_folio_cell(order, fund)
    cc = order.capital_commitment
    cc ? eg_gp_link(cc.folio_id, evergreen_folio_path(fund, cc)) : tag.span("New", class: "text-muted")
  end

  # Column headers for eg_gate_cells — the same four on every screen ("carried" follows the fund's
  # wording: "Deferred" in US terms). done: true once the dealing date is confirmed (past tense) — then the
  # column is "Filled", not "Paid": the gate has filled it, but the payout waits until it is marked paid
  # (the row's Settlement badge says Awaiting payment until then)
  def eg_gate_headers(fund, done: false)
    carried = eg_word(:carried, fund)
    safe_join([tag.th("Running total", class: "text-end"), tag.th(done ? "Filled" : "Will be paid", class: "text-end"),
               tag.th(done ? carried : "Will be #{EvergreenLabels.lower(carried)}", class: "text-end"), tag.th("At the gate")])
  end

  # The gate's outcome for a queued redemption: [running total, (will be) paid, (will be) carried, verdict badge].
  # Before confirming it is worded as what will happen — nothing is paid, carried or cancelled until then;
  # done: true (a confirmed date, rows from its fills) words it as what happened.
  def eg_gate_cells(row, gate, fund, done: false)
    return Array.new(3, "—") + [eg_badge(:grey, "alert-circle", "No NAV", "No approved NAV for class #{row.order.unit_type} yet, so it can't be valued against the gate.")] if row.outcome == :no_nav

    on = l(gate.dealing_date.date)
    paid = row.paid_units.to_d.positive? ? safe_join([evergreen_money(row.paid_cents, fund), tag.br, tag.small(eg_units(row.paid_units, fund:), class: "text-muted")]) : "—"
    carried = row.carried_units.to_d.positive? ? safe_join([evergreen_money(row.carried_cents, fund), tag.br, tag.small(eg_units(row.carried_units, fund:), class: "text-muted")]) : "—"
    # Where the unpaid rest goes — the same test the confirm uses (DealingConfirm#carry_forward):
    # with no later redemption date in the calendar it is not carried, the order closes on what was paid
    carried_word = EvergreenLabels.lower(eg_word(:carried, fund))
    rest = eg_gate_rest(row, gate, carried_word, done:) if row.carried_units.to_d.positive?
    nothing = gate.gate_method == "pro_rata" ? "Nothing" : "The gate is used up before this request, so nothing"
    badge = if done
              case row.outcome
              # Filled, not paid: the payout is a separate step (Mark paid) shown in the Settlement column
              when :full then eg_badge(:green, "check", "Filled in full", "Filled in full on #{on}; paid once the payout is marked paid.")
              when :part then eg_badge(:blue, "chart-pie", "Part-filled", "#{evergreen_money(row.paid_cents, fund)} was filled on #{on}; #{rest}.")
              else eg_badge(:grey, "arrow-forward", eg_word(:carried, fund), "#{nothing} was filled on #{on}; #{rest}.")
              end
            else
              case row.outcome
              when :full then eg_badge(:green, "check", "Will be paid in full", gate.gated? ? "Fits within the gate; paid on #{on}." : "No gate: paid in full on #{on}.")
              when :part then eg_badge(:blue, "chart-pie", "Will be part-filled", "#{evergreen_money(row.paid_cents, fund)} will be paid on #{on}; #{rest}.")
              else eg_badge(:grey, "arrow-forward", "Will be #{carried_word}", "#{nothing} will be paid on #{on}; #{rest}.")
              end
            end
    [evergreen_money(row.running_cents, fund), paid, carried, badge]
  end

  private

  # Where the unpaid rest goes. Before confirming: the same test the confirm uses (DealingConfirm#carry_forward) —
  # with no later redemption date in the calendar it is not carried and the order closes on what was paid.
  # After: a carried order has already moved to its new dealing date
  def eg_gate_rest(row, gate, carried_word, done:)
    if done
      moved = row.order.dealing_date_id != gate.dealing_date.id
      return moved ? "the rest was #{carried_word} to #{l(row.order.dealing_date.date)}" : "the rest was not #{carried_word} — there was no later redemption date in the calendar"
    end

    next_date = DealingRoll.next_date(row.order, gate.dealing_date)
    next_date ? "the rest will be #{carried_word} to #{l(next_date)}, at the front of the queue" : "the rest will not be #{carried_word} — there is no later redemption date in the calendar"
  end

  # F6: a part-filled redemption shows what is still to redeem — the same figure the gate columns and the
  # running total use — with the original request as a muted "of …" note and the earlier fills in a tooltip
  def eg_part_filled_amount_units(order, nav, tip, none)
    fund = order.fund
    done = order.filled_so_far
    dealt_tip = "#{eg_unit_count(done[:units])} #{eg_word(:units, fund)} (#{evergreen_money(done[:amount_cents], fund)}) were dealt on earlier " \
                "#{EvergreenLabels.lower(eg_word(:redemption_date, fund)).pluralize}; this is what is left of the request."
    of_note = ->(requested) { content_tag(:div, "of #{requested} requested", class: "small text-muted", title: dealt_tip, data: { bs_toggle: "tooltip" }) }
    if order.form == "amount"
      left = order.remaining_amount_cents
      [safe_join([evergreen_money(left, fund), of_note.call(evergreen_money(order.amount_cents, fund))]),
       nav ? eg_estimate(eg_unit_count(left / nav.nav_per_unit_cents.to_d), tip) : none]
    else
      left = order.remaining_units
      [nav ? eg_estimate(evergreen_money(left * nav.nav_per_unit_cents.to_d, fund), tip) : none,
       safe_join([eg_unit_count(left), (of_note.call(eg_unit_count(order.units)) if order.form == "units")].compact)]
    end
  end

  # A bare unit count for the Units column (the header names the unit; EvergreenWordingHelper#eg_units adds the word)
  def eg_unit_count(units)
    number_with_precision(units, precision: 4, delimiter: ",")
  end

  def eg_estimate(text, tip)
    content_tag(:span, "≈ #{text}", class: "text-muted", title: tip, data: { bs_toggle: "tooltip" })
  end
end
