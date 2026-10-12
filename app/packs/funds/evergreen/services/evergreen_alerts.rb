# Evergreen notifications (open-ended-funds § Notifications): who gets each internal alert, the
# per-fund on/off switch (EvergreenFundSetting#notify?), and send-once (EvergreenNotificationLog).
# Event hooks call the class methods below; EvergreenNotificationsJob runs the daily checks.
class EvergreenAlerts
  class << self
    # ---- Event hooks ----

    # A portal order: tell the relationship manager; a large redemption also goes to Compliance
    def order_placed(order)
      recipients = EvergreenRecipients.new(order.fund)
      on = order.received_at.to_date
      internal(:new_order, order, recipients.relationship_manager(order.investor), on:) if order.source == "portal"
      return unless order.redemption? && (pct = redemption_pct(order))
      return if pct < order.fund.evergreen_fund_setting.notification_number("large_redemption_pct")

      internal(:large_redemption, order, recipients.tagged(EvergreenRecipients::COMPLIANCE) + recipients.relationship_manager(order.investor), on:, pct: pct.round(2).to_s)
    end

    # A drafted or uploaded NAV: approvers (not the preparer); Fund accounting if the fee lags
    def nav_drafted(fund_nav)
      recipients = EvergreenRecipients.new(fund_nav.fund)
      # Dated by the NAV date: a re-draft or re-approval of the same NAV is not announced again
      internal(:nav_awaiting_approval, fund_nav, recipients.approvers(except: fund_nav.prepared_by), on: fund_nav.nav_date)
      internal(:fee_accrual_behind, fund_nav, recipients.tagged(EvergreenRecipients::ACCOUNTING), on: fund_nav.nav_date) if fee_accrual_behind?(fund_nav)
    end

    # An approved NAV: preparer and Fund ops; investors' NAV update; dealing dates that became ready
    def nav_approved(fund_nav)
      fund = fund_nav.fund
      recipients = EvergreenRecipients.new(fund)
      internal(:nav_approved, fund_nav, [fund_nav.prepared_by].compact + recipients.tagged(EvergreenRecipients::OPS), on: fund_nav.nav_date)
      if fund.evergreen_fund_setting.notify?(:nav_update)
        # Once per folio per NAV date, so a failure part-way never re-emails the folios already done
        folios_of_class(fund, fund_nav.unit_type, fund_nav.nav_date).each do |folio|
          safely(folio) { EvergreenNotificationLog.once(fund, :nav_update, folio, on: fund_nav.nav_date) { EvergreenNotifier.nav_update(folio, fund_nav) } }
        end
      end
      # Decision 3: ready_to_confirm checks the real (last) deadline, so no cut-off pre-filter here
      fund.dealing_dates.where(status: "open", date: ..(Time.zone.today + 1.year)).find_each { |dd| ready_to_confirm(dd) }
    end

    # Confirmed with redemptions carried forward: Compliance and Fund ops
    def dealing_confirmed(dealing_date)
      return unless dealing_date.dealing_fills.where(kind: "redemption").where("carried_units > 0").exists?

      recipients = EvergreenRecipients.new(dealing_date.fund)
      internal(:gate_applied, dealing_date, recipients.tagged(EvergreenRecipients::COMPLIANCE) + recipients.tagged(EvergreenRecipients::OPS), on: dealing_date.date)
    end

    # A subscription's money recorded and verified: tell the investor once
    def payment_verified(order)
      return unless order.subscription? && order.fully_paid?

      EvergreenNotificationLog.once(order.fund, :payment_received, order, on: order.dealing_date.date) { EvergreenNotifier.payment_received(order) }
    end

    # Documents generated from templates: approvers, once per dealing date per day
    def documents_generated(dealing_date)
      # Once per Generate run that made documents (spec), so it is not day-logged
      internal(:documents_awaiting_approval, dealing_date, EvergreenRecipients.new(dealing_date.fund).approvers, once: false)
    end

    # NAV approved and every deadline passed: Fund ops and approvers, once per dealing date.
    # Decision 3: "ready" uses the same rule as the Confirm button (the LAST deadline — subscription
    # cut-off and every class's notice — not only the cut-off), so it never says ready while blocked.
    def ready_to_confirm(dealing_date)
      return unless dealing_date.open? && dealing_date.deadlines_passed?
      return unless DealingPricer.preview(dealing_date).confirmable?

      recipients = EvergreenRecipients.new(dealing_date.fund)
      internal(:ready_to_confirm, dealing_date, recipients.tagged(EvergreenRecipients::OPS) + recipients.approvers, on: dealing_date.date)
    end

    # ---- Daily checks (EvergreenNotificationsJob) ----

    def daily(setting, today: Time.zone.today)
      fund = setting.fund
      reminders(fund, setting, today)
      cutoff_summaries(fund, today)
      # Decision 3: no cut-off pre-filter — a redemption-only date's last deadline is a notice deadline,
      # which can pass before its (unused) cut-off; ready_to_confirm checks the real deadlines
      fund.dealing_dates.where(status: "open", date: ..(today + 1.year)).find_each { |dd| safely(dd) { ready_to_confirm(dd) } }
      settlement_overdue(fund, today)
      units_unlocked(fund, setting, today) if setting.notify?(:units_unlocked)
    end

    # Summary lines for the dealing-date alerts (EvergreenOpsMailer). Values that need view helpers
    # are lambdas the mailer calls with itself.
    def date_lines(key, dealing_date)
      h = ApplicationController.helpers
      fund = dealing_date.fund
      money = ->(cents) { h.evergreen_money(cents, fund) }
      d = ->(date) { I18n.l(date, format: :email, locale: :en) }
      # The fund's wording (EvergreenLabels): "units" / "shares", "carried" / "deferred", ...
      lbl = ->(k) { EvergreenLabels.t(k, fund:) }
      orders = DealingOrder.where(dealing_date_id: dealing_date.id, status: DealingOrder::OPEN_STATUSES).includes(:investor, :capital_remittance)
      case key.to_s
      when "cutoff_summary", "ready_to_confirm"
        subs = orders.select(&:subscription?)
        reds = orders.select(&:redemption?)
        unpaid = dealing_date.pre_funded? ? subs.reject(&:fully_paid?) : []
        pricing = DealingPricer.preview(dealing_date)
        fate = fund.evergreen_fund_setting.unready_handling == "cancel" ? "will be cancelled" : "will roll"
        ["#{subs.size} subscriptions (#{money.call(subs.sum { |o| o.amount_cents.to_d })})",
         "#{unpaid.size} unpaid#{" (#{unpaid.map { |o| "#{o.investor.investor_name} #{money.call(o.amount_cents)}" }.join(', ')} — #{fate})" if unpaid.any?}",
         "#{pricing.unready.size - unpaid.size} not ready",
         "#{reds.size} redemptions (#{money.call(pricing.redemptions.sum(&:requested_value_cents))})",
         pricing.missing_navs.any? ? "Waiting on an approved NAV for class #{pricing.missing_navs.map(&:first).join(', ')} (newer than the one its previous date used — Decision 4)" : "NAV approved — ready to confirm"]
      when "gate_applied"
        dealing_date.dealing_fills.where(kind: "redemption").where("carried_units > 0").includes(dealing_order: :investor).map do |f|
          "#{f.dealing_order.investor.investor_name}: #{money.call(f.amount_cents)} paid, #{h.number_with_precision(f.carried_units, precision: 4, delimiter: ',')} #{lbl.call(:units)} #{EvergreenLabels.lower(lbl.call(:carried))}"
        end
      when "documents_awaiting_approval"
        fills = EvergreenDealingDocuments.awaiting_approval(dealing_date)
        notes = fills.count(&:subscription?)
        advices = fills.size - notes
        ["#{notes} #{EvergreenLabels.lower(lbl.call(:contract_note)).pluralize(notes)} and #{advices} #{EvergreenLabels.lower(lbl.call(:redemption_advice)).pluralize(advices)} to approve",
         "Open the #{EvergreenLabels.lower(lbl.call(:transaction_date))} and click Approve & send"]
      when "settlement_overdue"
        today = Time.zone.today
        rows = []
        due = DealingSettlement.payment_due_date(dealing_date)
        if due < today
          dealing_date.dealing_fills.joins(:capital_distribution_payment).where(capital_distribution_payments: { completed: false })
                      .includes(dealing_order: :investor).find_each do |f|
            rows << "#{f.dealing_order.investor.investor_name} #{money.call(f.net_payment_cents || f.amount_cents)}, due #{d.call(due)}"
          end
        end
        pay_by = dealing_date.date + fund.evergreen_fund_setting.pay_after_days.days
        if !dealing_date.pre_funded? && pay_by < today
          dealing_date.dealing_fills.where(kind: "subscription", fund_unit_id: nil).includes(dealing_order: :investor).find_each do |f|
            rows << "#{f.dealing_order.investor.investor_name} #{money.call(f.amount_cents)}, pay by #{d.call(pay_by)}"
          end
        end
        rows
      else []
      end
    end

    private

    # Send an internal alert once per record (per `on` day), only when switched on for the fund
    def internal(key, record, users, on: Time.zone.today, once: true, **params)
      fund = record.fund
      return unless fund.evergreen_fund_setting&.notify?(key)

      users = users.compact.uniq
      return if users.empty?

      deliver = -> { EvergreenOpsNotifier.with(record:, entity_id: fund.entity_id, email_method: key.to_s, **params).deliver_later(users) }
      once ? EvergreenNotificationLog.once(fund, key, record, on:, &deliver) : deliver.call
    end

    # One bad record must not stop a fund's other daily checks: report it and carry on
    def safely(record)
      yield
    rescue StandardError => e
      ErrorReport.notify(e, source: "EvergreenAlerts", message: "Evergreen notification failed for #{record.class.name} #{record.id}")
      nil
    end

    # Value of a redemption request as a % of its class NAV (latest approved)
    def redemption_pct(order)
      nav = FundNav.latest_approved(order.fund, order.unit_type, Time.zone.today)
      return nil unless nav&.nav_cents.to_d.positive?

      value = if order.amount_cents.to_d.positive? then order.amount_cents.to_d
              else begin
                order.resolved_units(nav_per_unit_cents: nav.nav_per_unit_cents)
              rescue StandardError
                0
              end.to_d * nav.nav_per_unit_cents.to_d
              end
      value / nav.nav_cents.to_d * 100
    end

    # Same rule as the NAV page and the approval refusal (EvergreenFeeCheck): never for an uploaded NAV,
    # a 0 % class or a NAV with no units
    def fee_accrual_behind?(fund_nav)
      EvergreenFeeCheck.accrual_message(fund_nav).present?
    end

    def folios_of_class(fund, unit_type, as_of)
      ids = FundUnit.where(fund_id: fund.id, unit_type:, issue_date: ..as_of).group(:capital_commitment_id).having("SUM(quantity) > 0").pluck(:capital_commitment_id)
      fund.capital_commitments.where(id: ids).includes(:investor)
    end

    # Payment reminder (pre-funded, unpaid) and action needed (journey unfinished), N days before cut-off
    def reminders(fund, setting, today)
      days = setting.notification_number("reminder_days").to_i
      dates = fund.dealing_dates.where(status: "open", cutoff_at: today.beginning_of_day..(today + days.days).end_of_day)
      DealingOrder.where(dealing_date_id: dates.select(:id), status: "pending").includes(:dealing_date).find_each do |order|
        safely(order) do
          EvergreenNotificationLog.once(fund, :payment_reminder, order, on: order.dealing_date.date) { EvergreenNotifier.payment_reminder(order) } if order.subscription? && order.dealing_date.pre_funded? && !order.fully_paid? && setting.notify?(:payment_reminder)
          EvergreenNotificationLog.once(fund, :action_needed, order, on: order.dealing_date.date) { EvergreenNotifier.action_needed(order) } if setting.journeys_for?(order.kind) && setting.notify?(:action_needed) && OrderJourneyStatus.waiting_on(order)
        end
      end
    end

    # The day after a cut-off (or later, if the job missed a day): one summary per dealing date
    def cutoff_summaries(fund, today)
      recipients = EvergreenRecipients.new(fund)
      fund.dealing_dates.where(status: "open", cutoff_at: ...today.beginning_of_day).find_each do |dd|
        next unless DealingOrder.exists?(dealing_date_id: dd.id)

        safely(dd) { internal(:cutoff_summary, dd, recipients.tagged(EvergreenRecipients::OPS), on: dd.date) }
      end
    end

    # Overdue settlements: the day after they fall due, then weekly while still overdue
    def settlement_overdue(fund, today)
      recipients = EvergreenRecipients.new(fund)
      fund.dealing_dates.where(status: "confirmed").find_each do |dd|
        overdue = overdue_payments(dd, today)
        next if overdue[:redemptions].zero? && overdue[:subscriptions].zero?
        next if today < overdue[:since]
        # Weekly while overdue: skip if an alert went out in the last 7 days (a missed day doesn't skip a week)
        next if EvergreenNotificationLog.exists?(key: "settlement_overdue", record_type: "DealingDate", record_id: dd.id, sent_on: (today - 6.days)..today)

        safely(dd) { internal(:settlement_overdue, dd, recipients.tagged(EvergreenRecipients::OPS), on: today) }
      end
    end

    def overdue_payments(dd, today)
      red_due = DealingSettlement.payment_due_date(dd)
      redemptions = red_due < today ? dd.dealing_fills.joins(:capital_distribution_payment).where(capital_distribution_payments: { completed: false }).count : 0
      sub_due = dd.date + dd.fund.evergreen_fund_setting.pay_after_days.days
      subscriptions = !dd.pre_funded? && sub_due < today ? dd.dealing_fills.where(kind: "subscription", fund_unit_id: nil).count : 0
      # Count from the obligation that is actually overdue (pre-funded dates have no pay-by date)
      due_dates = []
      due_dates << red_due if redemptions.positive?
      due_dates << sub_due if subscriptions.positive?
      { redemptions:, subscriptions:, since: (due_dates.min || red_due) + 1.day }
    end

    # Lots whose lock-up ends today: one email per folio with the units that became free
    def units_unlocked(fund, setting, today)
      fund.unit_types_list.each do |ut|
        term = setting.terms_for(ut)
        next unless term.lock_up?

        # Lots whose lock-up ends today: issue + n months == today. At a month end several issue days map
        # to it (29–31 Jan + 1 month = 28 Feb), so take the whole tail of that month
        first = today.advance(months: -term.lock_up_months)
        last = today == today.end_of_month ? first.end_of_month : first
        FundUnit.where(fund_id: fund.id, unit_type: ut, issue_date: first..last).where("quantity > 0")
                .group(:capital_commitment_id).sum(:quantity).each do |folio_id, units|
          folio = fund.capital_commitments.find_by(id: folio_id)
          next unless folio

          safely(folio) { EvergreenNotificationLog.once(fund, :units_unlocked, folio, on: today) { EvergreenNotifier.units_unlocked(folio, units) } }
        end
      end
    end
  end
end
