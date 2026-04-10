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

  # Renders an area chart showing the timeline of KYC registrations.
  # Uses direct SQL to bypass Groupdate's UTC requirement.
  def kyc_onboarding_timeline_chart(records)
    # Group by date using MySQL DATE function and pluck to avoid Groupdate interception
    # Qualifying created_at to avoid ambiguity in joined queries
    data = records.group(Arel.sql("DATE(investor_kycs.created_at)")).pluck(Arel.sql("DATE(investor_kycs.created_at), count(*)"))

    area_chart data, title: "KYC Onboarding Timeline", id: "kyc_onboarding_timeline_chart", library: {
      **chart_theme_color
    }
  end
end
