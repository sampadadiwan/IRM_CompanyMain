# Internal evergreen alerts (open-ended-funds § Notifications). One template: a title, a few summary
# lines and a link to the record. Dates use l(date) → "Mon dd, yyyy" in emails (EmailDateLocalization).
class EvergreenOpsMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper
  helper EvergreenNavHelper
  helper EvergreenWordingHelper

  KEYS = %w[new_order nav_awaiting_approval nav_approved cutoff_summary ready_to_confirm gate_applied
            large_redemption settlement_overdue fee_accrual_behind documents_awaiting_approval].freeze

  class << self
    # Subject / in-app message, from the record (spec NOTIF › Internal alerts)
    def title(key, record, pct: nil)
      h = ApplicationController.helpers
      fund = record.fund
      # The fund's wording (EvergreenLabels): "units" / "shares", "carried" / "deferred"
      lbl = ->(key) { EvergreenLabels.t(key, fund:) }
      text = case key.to_s
             when "new_order"
               "New #{EvergreenLabels.lower(lbl.call(record.kind))}: #{record.investor.investor_name} #{requested(record, h)} for #{d(record.dealing_date.date)}"
             when "large_redemption"
               "Large redemption: #{record.investor.investor_name} #{requested(record, h)} (#{pct} % of Class #{record.unit_type} NAV)"
             when "nav_awaiting_approval"
               # R9.13: say so when the draft also needs a late management fee decision before it can be approved
               late = !record.uploaded? && EvergreenLateFees.call(record.fund, record.unit_type, record.nav_date, draft: record).outstanding_cents.positive?
               "NAV awaiting approval: Class #{record.unit_type}, #{d(record.nav_date)}#{' — needs a late management fee decision' if late}"
             when "nav_approved"
               "NAV approved: Class #{record.unit_type}, #{d(record.nav_date)}, #{h.evergreen_money(record.nav_per_unit_cents, fund)}"
             when "fee_accrual_behind"
               "Management fee accrued only to #{record.mgmt_fee_accrued_to ? d(record.mgmt_fee_accrued_to) : 'nothing yet'} — " \
               "run the fee formula to #{d(record.nav_date)}, then recalculate (it can't be approved until then)"
             when "cutoff_summary" then "Cut-off passed: #{d(record.date)}"
             when "ready_to_confirm" then "#{d(record.date)} is ready to confirm"
             when "gate_applied"
               fills = record.dealing_fills.where(kind: "redemption").includes(:dealing_order)
               carried_fills = fills.select { |f| f.carried_units.to_d.positive? }
               # Amount requests carry exactly what was asked minus what was paid; unit requests at this NAV
               carried = carried_fills.sum do |f|
                 order = f.dealing_order
                 if order.amount_cents.to_d.positive? && !order.all_units && order.units.blank?
                   order.amount_cents.to_d - order.dealing_fills.joins(:dealing_date).where(dealing_dates: { date: ..record.date }).sum(:amount_cents).to_d
                 else
                   (f.carried_units.to_d * f.nav_per_unit_cents.to_d).round(0)
                 end
               end
               nxt = carried_fills.first&.dealing_order&.dealing_date&.date
               "Gate applied on #{d(record.date)}: #{h.evergreen_money(fills.sum(:amount_cents), fund)} paid, " \
                 "#{h.evergreen_money(carried, fund)} #{EvergreenLabels.lower(lbl.call(:carried))}#{" to #{d(nxt)}" if nxt && nxt != record.date}"
             when "settlement_overdue" then "Settlement overdue on #{d(record.date)}"
             when "documents_awaiting_approval" then "Documents awaiting approval for #{d(record.date)}"
             end
      "#{fund.name}: #{text}"
    end

    def link(record)
      h = Rails.application.routes.url_helpers
      case record
      when DealingOrder then h.evergreen_order_path(record.fund_id, record.id)
      when FundNav then h.evergreen_nav_path(record.fund_id, record.id)
      when DealingDate then h.evergreen_dealing_date_path(record.fund_id, record.id)
      else h.fund_path(record.fund_id)
      end
    end

    # Email dates are always "Mon dd, yyyy" in English (CLAUDE.md)
    def d(date) = I18n.l(date, format: :email, locale: :en)

    def requested(order, h)
      units = EvergreenLabels.t(:units, fund: order.fund)
      return "all #{units}" if order.all_units
      return "#{h.number_with_precision(order.units, precision: 4, delimiter: ',')} #{units}" if order.units.present?

      h.evergreen_money(order.amount_cents, order.fund)
    end
  end

  before_action :set_record
  def set_record
    @record = params[:record_type].constantize.find(params[:record_id])
    @fund = @record.fund
  end

  KEYS.each do |key|
    define_method(key) do
      @title = self.class.title(key, @record, pct: params[:pct])
      @lines = lines_for(key)
      @link = record_url
      send_mail(subject: @title, template_path: "evergreen_ops_mailer", template_name: "alert")
    end
  end

  private

  # Absolute link for the email (ActionMailer's default_url_options host)
  def record_url
    case @record
    when DealingOrder then evergreen_order_url(@record.fund_id, @record.id)
    when FundNav then evergreen_nav_url(@record.fund_id, @record.id)
    when DealingDate then evergreen_dealing_date_url(@record.fund_id, @record.id)
    else fund_url(@record.fund_id)
    end
  end

  def money(cents) = view_context.evergreen_money(cents, @fund)
  def units(u) = view_context.number_with_precision(u, precision: 4, delimiter: ",")
  # The fund's evergreen wording for a label key
  def label(key) = EvergreenLabels.t(key, fund: @fund)

  # The summary lines for each alert, from the record
  def lines_for(key)
    case key
    when "new_order", "large_redemption"
      o = @record
      date_label = label(o.subscription? ? :subscription_date : :redemption_date)
      ["Class #{o.unit_type}, #{EvergreenLabels.lower(label(:capital_commitment))} #{o.capital_commitment&.folio_id || 'new'}",
       "#{date_label} #{self.class.d(o.dealing_date.date)} (cut-off #{self.class.d(o.dealing_date.cutoff_at.to_date)})"]
    when "nav_awaiting_approval", "nav_approved", "fee_accrual_behind"
      n = @record
      ["NAV #{money(n.nav_cents)} · #{label(:nav_per_unit)} #{view_context.evergreen_nav_per_unit(n.nav_per_unit_cents)} · " \
       "#{units(n.units_outstanding)} #{label(:units)}",
       "Source: #{n.source.humanize}"]
    else
      EvergreenAlerts.date_lines(key, @record)
    end
  end
end
