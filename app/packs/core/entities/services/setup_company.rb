class SetupCompany < Trailblazer::Operation
  step :setup_folders
  step :setup_capital_call_journeys
  step :setup_capital_distribution_journeys
  step :setup_investor_kyc_journeys
  step :setup_kpi_report_journeys

  def setup_folders(_ctx, entity:, **)
    if entity.root_folder.blank?
      entity.update_column(:root_folder_id, Folder.create(name: "/", entity_id: entity.id, level: 0, folder_type: :regular).id)
      entity.reload
    end
    true
  end

  # Fund managers get the two capital call journeys and the rules that launch them on new calls
  # (capital-call-journey). Idempotent; existing calls are never touched.
  # Worked examples H1 — openspec/changes/archive/2026-10-02-capital-call-journey/design.md#worked-examples
  def setup_capital_call_journeys(_ctx, entity:, **)
    CapitalCallJourneySetup.call(entity:) if entity.entity_type == "Investment Fund"
    true
  end

  # And the two capital distribution journeys, the same way (capital-distribution-journey).
  # Worked examples H1 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples
  def setup_capital_distribution_journeys(_ctx, entity:, **)
    CapitalDistributionJourneySetup.call(entity:) if entity.entity_type == "Investment Fund"
    true
  end

  # And the investor KYC journey, for Investment and Angel Funds (investor-kyc-journey).
  # Worked examples H1 — openspec/changes/investor-kyc-journey/design.md#worked-examples
  def setup_investor_kyc_journeys(_ctx, entity:, **)
    InvestorKycJourneySetup.call(entity:) if InvestorKycJourneySetup.available_for?(entity)
    true
  end

  # And the KPI report journey, for funds that use KPIs (kpi-report-journey).
  # Worked examples H1 — openspec/changes/kpi-report-journey/design.md#worked-examples
  def setup_kpi_report_journeys(_ctx, entity:, **)
    KpiReportJourneySetup.call(entity:) if KpiReportJourneySetup.available_for?(entity)
    true
  end
  # rubocop:enable Rails/SkipsModelValidations
end
