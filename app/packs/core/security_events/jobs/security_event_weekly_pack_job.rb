# frozen_string_literal: true

# The Monday security review pack (OWASP review 2026-11 M11, design card ⑧, D11, H34): last week's events across every
# firm in this region, as a five-sheet spreadsheet, emailed to the region's SECURITY_EVENTS_WEEKLY_TO
# (support@caphive.com in both IN and US). Each region's box runs its own job and sends only its own events, so IN
# and US stay independent; the subject names the region so the two packs stay apart in one inbox.
#
# Unset SECURITY_EVENTS_WEEKLY_TO → a warning in the log and no email (spec "Setting missing").
# Runs from sidekiq-cron on Monday morning local time (config/initializers/sidekiq.rb).
class SecurityEventWeeklyPackJob < ApplicationJob
  queue_as :low
  self.log_arguments = false
  retry_on StandardError, attempts: 3
  SETTING = "SECURITY_EVENTS_WEEKLY_TO"

  # @param today [String, nil] ISO date the run is for (tests); defaults to today in the app's time zone
  def perform(today = nil)
    to_email = ENV.fetch(SETTING, "").strip
    if to_email.empty?
      # Spec "Setting missing" — nothing is sent from a box nobody configured
      Rails.logger.warn("[security_event] weekly_pack_skipped #{SETTING} is not set")
      return
    end

    # The previous Monday 00:00 to Sunday 23:59, local time
    week_end = (today ? Date.iso8601(today) : Time.zone.today).beginning_of_week - 1.day
    week_start = week_end.beginning_of_week
    week = SecurityEvent.for_period(week_start.beginning_of_day..week_end.end_of_day)

    xlsx = SecurityEventWorkbook.new
                                .add_events("All", week)
                                .add_failed_sign_ins_by_account(week)
                                .add_events("Access", week.where(category: "access"))
                                .add_events("Support", week.where(category: "support"))
                                .add_events("Exports", week.where(kind: "data.exported"))
                                .to_stream
    SecurityEventsMailer.with(to_email:, region: SecurityEvents.region, xlsx:, counts: counts(week),
                              from: week_start.iso8601, to: week_end.iso8601,
                              subject: subject(week_start, week_end)).weekly_pack.deliver_now
  end

  private

  # "[IN] Security events 02 Nov – 08 Nov 2026" (an explicit subject-line format, English month names)
  def subject(week_start, week_end)
    "[#{SecurityEvents.region}] Security events #{I18n.l(week_start, format: '%d %b', locale: :en)} – " \
      "#{I18n.l(week_end, format: '%d %b %Y', locale: :en)}"
  end

  # The email's summary lines, one grouped query
  def counts(week)
    grouped = week.unscope(:order).group(:category, :outcome, :kind).count
    sum = ->(&rule) { grouped.sum { |(category, outcome, kind), n| rule.call(category, outcome, kind) ? n : 0 } }
    { "all" => grouped.values.sum,
      "failed_sign_ins" => sum.call { |c, o, _k| c == "sign_in" && o == "failure" },
      "access" => sum.call { |c, _o, _k| c == "access" },
      "support" => sum.call { |c, _o, _k| c == "support" },
      "exports" => sum.call { |_c, _o, k| k == "data.exported" } }
  end
end
