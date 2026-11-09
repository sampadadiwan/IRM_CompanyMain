module InvestorKycAnalyticsHelper
  # Renders a donut chart showing KYC verification status (Verified vs Unverified).
  # Clickable: Filters the table by verification status.
  def kyc_verification_status_chart(records)
    data = records.group(:verified).count.transform_keys { |k| k ? "Verified" : "Unverified" }

    pie_chart data, donut: true, title: "Verification Status", id: "kyc_verification_status_chart", library: {
      **chart_theme_color,
      **clickable_chart_options("q[verified_eq]", frame_id: 'investor_kycs_frame')
    }
  end

  # Renders a donut chart showing KYC completion status (Completed vs Pending).
  # Clickable: Filters the table by completion status.
  def kyc_completion_status_chart(records)
    data = records.group(:completed_by_investor).count.transform_keys { |k| k ? "Completed" : "Pending" }

    pie_chart data, donut: true, title: "Completion Status", id: "kyc_completion_status_chart", library: {
      **chart_theme_color,
      **clickable_chart_options("q[completed_by_investor_eq]", frame_id: 'investor_kycs_frame')
    }
  end

  # Renders a donut chart showing the distribution of KYC types (Individual vs Non-Individual).
  # Clickable: Filters the table by KYC type.
  def kyc_type_distribution_chart(records)
    data = records.group(:kyc_type).count

    pie_chart data, donut: true, title: "KYC Type Distribution", id: "kyc_type_distribution_chart", library: {
      **chart_theme_color,
      **clickable_chart_options("q[kyc_type_eq]", frame_id: 'investor_kycs_frame')
    }
  end

  # Renders a staircase of the running total of KYCs created over time.
  # A per-day count would be 1 on almost every day (KYCs arrive a few at a time), and an area chart
  # joins those points into a flat band at 1 — so plot the cumulative total, stepped, instead.
  # Uses direct SQL to bypass Groupdate's UTC requirement.
  def kyc_onboarding_timeline_chart(records)
    # Count KYCs per creation day in SQL (DATE() works on MySQL and SQLite).
    # - unscope(:order): the list's sort column is not in the GROUP BY (MySQL rejects it)
    # - COUNT(DISTINCT id): the list's policy scope can join duplicate rows; its .distinct does not dedupe a grouped count
    # - created_at is qualified to avoid ambiguity in joined queries
    day_sql = "DATE(investor_kycs.created_at)"
    per_day = records.unscope(:order)
                     .group(Arel.sql(day_sql))
                     .order(Arel.sql(day_sql))
                     .pluck(Arel.sql("#{day_sql}, COUNT(DISTINCT investor_kycs.id)"))

    # Turn per-day counts into a running total, e.g. [[Jun 3, 1], [Nov 6, 1]] -> {Jun 3 => 1, Nov 6 => 2}.
    # MySQL returns Date objects, SQLite returns "YYYY-MM-DD" strings; normalise both to Date.
    total = 0
    data = per_day.to_h { |day, count| [day.to_date, total += count] }
    # Carry the latest total to today so the last step does not end at the last KYC's date.
    data[Time.zone.today] = total if data.any? && data.keys.max < Time.zone.today

    area_chart data, title: "KYC Onboarding Timeline", ytitle: "Total KYCs", id: "kyc_onboarding_timeline_chart", library: {
      **chart_theme_color,
      # step: hold each total flat until the next KYC, instead of sloping between creation dates
      plotOptions: { area: { step: "left" } }
    }
  end

  # Renders a chart for a specific key within the json_fields.
  # Supports both 'pie' and 'bar' chart types.
  def kyc_json_field_chart(records, key, chart_type = 'pie')
    # Sanitize key to allow only alphanumeric and underscores for safety
    safe_key = key.to_s.gsub(/[^a-zA-Z0-9_]/, '')
    return if safe_key.blank?

    # Use MySQL-specific JSON extraction and grouping
    data = records.group(Arel.sql("JSON_UNQUOTE(investor_kycs.json_fields->'$.#{safe_key}')")).count

    # Clean up results: Handle nulls and empty strings
    data = data.transform_keys { |k| k.present? && k != "null" ? k : "N/A" }

    title = safe_key.humanize.titleize
    chart_id = "kyc_json_#{safe_key}_chart"

    options = {
      title: title,
      id: chart_id,
      library: {
        **chart_theme_color,
        **clickable_chart_options("q[json_fields.#{safe_key}_eq]", frame_id: 'investor_kycs_frame')
      }
    }

    if chart_type == 'bar'
      bar_chart data, **options
    else
      pie_chart data, donut: true, **options
    end
  end
end
