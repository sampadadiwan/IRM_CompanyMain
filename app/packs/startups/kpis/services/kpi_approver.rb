class KpiApprover
  def self.call(kpi_id, user_id)
    kpi = Kpi.find(kpi_id)
    raise "KPI is already approved" if kpi.approved?

    # Find existing approved KPI for the same metric/report/company
    existing_approved = Kpi.approved.find_by(
      name: kpi.name,
      kpi_report_id: kpi.kpi_report_id,
      portfolio_company_id: kpi.portfolio_company_id,
      entity_id: kpi.entity_id
    )

    Kpi.transaction do
      if existing_approved
        # Overwrite the approved record with the unapproved data
        existing_approved.update!(
          value: kpi.value,
          display_value: kpi.display_value,
          notes: kpi.notes,
          investor_kpi_mapping_id: kpi.investor_kpi_mapping_id,
          approved_by_user_id: user_id,
          approved_at: Time.zone.now
        )
        # Destroy the unapproved staging record
        kpi.destroy!
        @result_kpi = existing_approved
      else
        # No approved record existed, so just approve this one
        kpi.update!(status: :approved, approved_by_user_id: user_id, approved_at: Time.zone.now)
        @result_kpi = kpi
      end
    end

    @result_kpi
  end
end
