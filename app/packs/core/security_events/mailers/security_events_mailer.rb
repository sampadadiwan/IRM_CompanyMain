# frozen_string_literal: true

# Security event trail emails (OWASP review 2026-11 M11): the admin alert (card ⑦), the Download (card ⑥) and the
# Monday pack (card ⑧). Every email says why the reader got it and what to do. Dates render "Mon dd, yyyy" through
# EmailDateLocalization (bare l(...) in the views).
class SecurityEventsMailer < ApplicationMailer
  # H32 / H33 — one recipient per notification (SecurityEventNotifier)
  def admin_alert
    @event = SecurityEvent.find(params[:security_event_id])
    @headline = SecurityEventAlert.headline(@event)
    send_mail(subject: "Security alert: #{@headline}")
  end

  # H31 — the requester's spreadsheet of the filtered events
  def download
    # @period_* — not @from / @to, which ApplicationMailer uses for the addresses
    @period_from, @period_to = Array(params[:period]).map { |value| iso_date(value) }
    attachments["security_events.xlsx"] = { mime_type: Mime[:xlsx].to_s, content: params[:xlsx] }
    send_mail(subject: "Your security events spreadsheet")
  end

  # H34 — the Monday SOC 2 pack, to the region's SECURITY_EVENTS_WEEKLY_TO (support@caphive.com), not to a user
  def weekly_pack
    @period_from = Date.iso8601(params[:from])
    @period_to = Date.iso8601(params[:to])
    @region = params[:region]
    @counts = params[:counts] || {}
    attachments["security_events_#{@region.downcase}_#{@period_from.iso8601}.xlsx"] = { mime_type: Mime[:xlsx].to_s, content: params[:xlsx] }
    mail(to: params[:to_email], subject: params[:subject])
  end

  private

  def iso_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
