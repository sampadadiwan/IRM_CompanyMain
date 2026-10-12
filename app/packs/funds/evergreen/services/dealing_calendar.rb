# Expands an evergreen fund's dealing calendars into dates, cut-offs and notice deadlines.
# Pure: reads the setting only. Business days are Monday–Friday (no holiday calendar; holidays are
# handled by entering custom dates).
# Worked examples H7, H16, E3, E14, E15 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingCalendar
  class NoDate < StandardError; end

  # How far ahead next_dealing_date looks before giving up
  HORIZON_YEARS = 3

  class << self
    # Dealing dates of one kind between two dates (inclusive), business-day adjusted.
    def dates(setting, kind, from:, to:)
      calendar = calendar_for(setting, kind)
      if calendar == "custom"
        custom_dates(setting, kind).map { |d| next_business_day(d) }.grep(from..to).uniq.sort
      else
        period_starts(calendar, from.beginning_of_year, to).filter_map do |start|
          d = dealing_day_in(setting, calendar, start)
          d if d.between?(from, to)
        end.uniq.sort
      end
    end

    # Union of subscription and redemption dates — the dealing dates the fund has.
    def all_dates(setting, from:, to:)
      (dates(setting, :subscription, from:, to:) + dates(setting, :redemption, from:, to:)).uniq.sort
    end

    def dealing_date?(setting, kind, date)
      dates(setting, kind, from: date, to: date).include?(date)
    end

    # Subscription cut-off: end of the day N days before the dealing date.
    # Worked example H7 (2 Nov 2026 → cut-off 28 Oct)
    def cutoff_at(setting, date)
      (date - setting.subscription_cutoff_days.days).in_time_zone.end_of_day
    end

    # Redemption notice deadline for a class: end of the day notice_days before the dealing date.
    def notice_deadline(setting, date, unit_type)
      (date - setting.terms_for(unit_type).notice_days.days).in_time_zone.end_of_day
    end

    # The earliest dealing date of a kind whose cut-off (subscriptions) or notice deadline
    # (redemptions) the received time meets.
    # Worked examples E14 (after cut-off → following date), E15 (inside notice → next quarter)
    def next_dealing_date(setting, kind, unit_type, received_at)
      from = received_at.to_date
      dates(setting, kind, from:, to: from + HORIZON_YEARS.years).each do |date|
        deadline = kind.to_s == "subscription" ? cutoff_at(setting, date) : notice_deadline(setting, date, unit_type)
        return date if received_at <= deadline
      end
      raise NoDate, "No #{EvergreenLabels.lower(EvergreenLabels.t(kind.to_s == 'subscription' ? :subscription_date : :redemption_date, fund: setting.fund))} is available — check the fund's dealing calendar"
    end

    # The gate period a date falls in: the date itself, its calendar quarter or its year.
    def gate_period_range(setting, date)
      case setting.gate_period
      when "quarter" then date.all_quarter
      when "year" then date.all_year
      else date..date
      end
    end

    def next_business_day(date)
      date += 1.day while date.saturday? || date.sunday?
      date
    end

    def previous_business_day(date)
      date -= 1.day while date.saturday? || date.sunday?
      date
    end

    private

    def calendar_for(setting, kind)
      kind.to_s == "subscription" ? setting.subscription_calendar : setting.redemption_calendar
    end

    def custom_dates(setting, kind)
      raw = kind.to_s == "subscription" ? setting.subscription_dates : setting.redemption_dates
      Array(raw).compact_blank.map { |d| d.is_a?(Date) ? d : Date.parse(d.to_s) }
    end

    # First day of each period (calendar months, quarters, halves, years) from start to `to`
    def period_starts(calendar, start, to)
      step = { "monthly" => 1, "quarterly" => 3, "semi_annual" => 6, "annual" => 12 }.fetch(calendar)
      starts = []
      d = start
      while d <= to
        starts << d
        d = d.advance(months: step)
      end
      starts
    end

    # The dealing day within a period: first business day, last business day, or day N (moved to
    # the next business day).
    def dealing_day_in(setting, calendar, start)
      months = { "monthly" => 1, "quarterly" => 3, "semi_annual" => 6, "annual" => 12 }.fetch(calendar)
      case setting.dealing_day
      when "last" then previous_business_day(start.advance(months: months) - 1.day)
      when "day_n" then next_business_day(start.change(day: setting.dealing_day_n.to_i.clamp(1, 28)))
      else next_business_day(start)
      end
    end
  end
end
