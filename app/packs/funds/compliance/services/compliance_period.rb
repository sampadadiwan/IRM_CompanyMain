# Period arithmetic for duty schedules, by the pack's period basis (R20):
#   fy_apr   — financial year April–March; quarters Q1 Apr–Jun … Q4 Jan–Mar; "FY27" = Apr 2026 – Mar 2027
#   calendar — calendar quarters and years
# Worked examples H61, E118, E119, E120, E121 — openspec/changes/fund-compliance-monitoring/business-rules.md
module CompliancePeriod
  module_function

  # [period_key, period_end] for the period of `schedule` that contains `date`
  def for(date, schedule, basis)
    case schedule
    when "quarterly" then quarter(date, basis)
    when "half_yearly" then half(date, basis)
    else year(date, basis)
    end
  end

  def quarter(date, basis)
    q_end = date.end_of_quarter
    return ["#{date.year}-Q#{((date.month - 1) / 3) + 1}", q_end] if basis == "calendar"

    # FY quarters: Apr–Jun = Q1 … Jan–Mar = Q4
    fy = fy_number(date)
    q = (((date.month - 4) % 12) / 3) + 1
    ["FY#{format('%02d', fy % 100)}-Q#{q}", q_end]
  end

  def half(date, basis)
    if basis == "calendar"
      h = date.month <= 6 ? 1 : 2
      return ["#{date.year}-H#{h}", h == 1 ? Date.new(date.year, 6, 30) : Date.new(date.year, 12, 31)]
    end
    fy = fy_number(date)
    h = date.month.between?(4, 9) ? 1 : 2
    ["FY#{format('%02d', fy % 100)}-H#{h}", h == 1 ? Date.new(fy - 1, 9, 30) : Date.new(fy, 3, 31)]
  end

  def year(date, basis)
    return [date.year.to_s, Date.new(date.year, 12, 31)] if basis == "calendar"

    fy = fy_number(date)
    ["FY#{format('%02d', fy % 100)}", Date.new(fy, 3, 31)]
  end

  # The financial year is named by the year it ends in March (Apr 2026 – Mar 2027 = FY27)
  def fy_number(date)
    date.month >= 4 ? date.year + 1 : date.year
  end
end
