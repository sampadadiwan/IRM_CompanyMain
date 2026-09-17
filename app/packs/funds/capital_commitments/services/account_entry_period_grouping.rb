# Shared SQL for bucketing account_entries.reporting_date into month/quarter/year
# periods. Extracted so AccountEntryChartsHelper and AccountEntryReport group
# entries into identical period boundaries instead of drifting apart over time.
#
# Production/development run on MySQL; the test/cucumber environment runs SQLite
# (see config/database.yml), and the two have no common date-arithmetic syntax, so
# the grouping SQL is generated per-adapter rather than as one dialect-neutral string.
module AccountEntryPeriodGrouping
  def self.group_field_sql(aggregate_by, connection = ActiveRecord::Base.connection)
    if connection.adapter_name.match?(/mysql/i)
      mysql_group_field_sql(aggregate_by)
    else
      sqlite_group_field_sql(aggregate_by)
    end
  end

  def self.mysql_group_field_sql(aggregate_by)
    case aggregate_by.to_s.downcase
    when 'year'
      "DATE_FORMAT(reporting_date, '%Y-12-31')"
    when 'month'
      "LAST_DAY(reporting_date)"
    else # quarter
      "LAST_DAY(DATE_ADD(DATE_FORMAT(reporting_date, '%Y-01-01'), INTERVAL (QUARTER(reporting_date) * 3 - 1) MONTH))"
    end
  end

  def self.sqlite_group_field_sql(aggregate_by)
    case aggregate_by.to_s.downcase
    when 'year'
      "date(reporting_date, 'start of year', '+1 year', '-1 day')"
    when 'month'
      "date(reporting_date, 'start of month', '+1 month', '-1 day')"
    else # quarter
      "date(reporting_date, 'start of year', " \
        "'+' || ((CAST(strftime('%m', reporting_date) AS INTEGER) - 1) / 3 + 1) * 3 || ' months', '-1 day')"
    end
  end
end
