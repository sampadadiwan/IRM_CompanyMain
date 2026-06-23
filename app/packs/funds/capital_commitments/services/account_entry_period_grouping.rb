# Shared SQL for bucketing account_entries.reporting_date into month/quarter/year
# periods. Extracted so AccountEntryChartsHelper and AccountEntryReport group
# entries into identical period boundaries instead of drifting apart over time.
module AccountEntryPeriodGrouping
  def self.group_field_sql(aggregate_by)
    case aggregate_by.to_s.downcase
    when 'year'
      "DATE_FORMAT(reporting_date, '%Y-12-31')"
    when 'month'
      "LAST_DAY(reporting_date)"
    else # quarter
      "LAST_DAY(DATE_ADD(DATE_FORMAT(reporting_date, '%Y-01-01'), INTERVAL (QUARTER(reporting_date) * 3 - 1) MONTH))"
    end
  end
end
