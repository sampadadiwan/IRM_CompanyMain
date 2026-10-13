# Registers every workflow check class with WorkflowChecks::Registry. Checks are looked up by the
# key stored on a workflow step, so they must be registered before any evaluation runs. Wrapped in
# to_prepare so a code reload in development re-registers the reloaded classes.
#
# Capital call checks: app/packs/funds/capital_calls/workflow_checks/capital_call/.
# Capital distribution checks: app/packs/funds/capital_distributions/workflow_checks/capital_distribution/
# (Worked examples H2 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples).
# Investor KYC checks: app/packs/core/investor_kycs/workflow_checks/investor_kyc/
# (Worked examples H2 — openspec/changes/investor-kyc-journey/design.md#worked-examples).
# Evergreen order checks: app/packs/funds/evergreen/workflow_checks/dealing_order/
# (Worked examples H12–H15 — openspec/changes/open-ended-funds/design.md#worked-examples).
# KPI report checks: app/packs/startups/kpis/workflow_checks/kpi_report/
# (Worked examples H1 — openspec/changes/kpi-report-journey/design.md#worked-examples).
Rails.application.config.to_prepare do
  WorkflowChecks::Registry.reset!

  # Class names, constantized here at boot (never from user input)
  check_classes = %w[
    WorkflowChecks::CapitalCall::CreateRemittances
    WorkflowChecks::CapitalCall::AddCallNoticeTemplate
    WorkflowChecks::CapitalCall::GenerateNotices
    WorkflowChecks::CapitalCall::ApproveNotices
    WorkflowChecks::CapitalCall::ReviewEmail
    WorkflowChecks::CapitalCall::CheckPreview
    WorkflowChecks::CapitalCall::ApproveCall
    WorkflowChecks::CapitalCall::SendNotices
    WorkflowChecks::CapitalCall::CollectPayments
    WorkflowChecks::CapitalCall::VerifyRemittances
    WorkflowChecks::CapitalCall::AllocateUnits
    WorkflowChecks::CapitalCall::NoticesNotApplicable
    WorkflowChecks::CapitalCall::ReviewNotNeeded
    WorkflowChecks::CapitalCall::Imported
    WorkflowChecks::CapitalCall::NoUnitPrices
    WorkflowChecks::CapitalDistribution::CreatePayments
    WorkflowChecks::CapitalDistribution::GenerateNotices
    WorkflowChecks::CapitalDistribution::ApproveNotices
    WorkflowChecks::CapitalDistribution::ReviewEmail
    WorkflowChecks::CapitalDistribution::CheckPreview
    WorkflowChecks::CapitalDistribution::ApproveDistribution
    WorkflowChecks::CapitalDistribution::CompletePayments
    WorkflowChecks::CapitalDistribution::EmailInvestors
    WorkflowChecks::CapitalDistribution::RedeemUnits
    WorkflowChecks::CapitalDistribution::NoEmail
    WorkflowChecks::CapitalDistribution::NoticesNotUsed
    WorkflowChecks::CapitalDistribution::ReviewNotNeeded
    WorkflowChecks::CapitalDistribution::Imported
    WorkflowChecks::CapitalDistribution::NoUnitPrices
    WorkflowChecks::InvestorKyc::ReviewEmail
    WorkflowChecks::InvestorKyc::CheckPreview
    WorkflowChecks::InvestorKyc::SendForm
    WorkflowChecks::InvestorKyc::Submit
    WorkflowChecks::InvestorKyc::UploadDocuments
    WorkflowChecks::InvestorKyc::ValidateDocuments
    WorkflowChecks::InvestorKyc::RunAml
    WorkflowChecks::InvestorKyc::ClearAmlMatch
    WorkflowChecks::InvestorKyc::ReviewKyc
    WorkflowChecks::InvestorKyc::Verify
    WorkflowChecks::InvestorKyc::ReviewNotNeeded
    WorkflowChecks::InvestorKyc::FilledByFund
    WorkflowChecks::InvestorKyc::NoRequiredDocuments
    WorkflowChecks::InvestorKyc::AmlOff
    WorkflowChecks::InvestorKyc::NoAmlMatch
    WorkflowChecks::KpiReport::SetupMappings
    WorkflowChecks::KpiReport::SendRequest
    WorkflowChecks::KpiReport::Submit
    WorkflowChecks::KpiReport::Import
    WorkflowChecks::KpiReport::Approve
    WorkflowChecks::KpiReport::Close
    WorkflowChecks::KpiReport::SendCompletionEmail
    WorkflowChecks::KpiReport::FundUploaded
    WorkflowChecks::DealingOrder::CheckInvestorKyc
    WorkflowChecks::DealingOrder::CollectSignedForm
    WorkflowChecks::DealingOrder::VerifyRequest
    WorkflowChecks::DealingOrder::AcceptOrder
    WorkflowChecks::DealingOrder::CollectMoney
    WorkflowChecks::DealingOrder::ReadyToDeal
    WorkflowChecks::DealingOrder::Allotted
    WorkflowChecks::DealingOrder::Paid
    WorkflowChecks::DealingOrder::Cancelled
    WorkflowChecks::DealingOrder::NotSubscription
    WorkflowChecks::DealingOrder::NotRedemption
    WorkflowChecks::DealingOrder::MoneyNotNeeded
    WorkflowChecks::DealingDate::CollectMoney
    WorkflowChecks::DealingDate::ApproveNav
    WorkflowChecks::DealingDate::Confirm
    WorkflowChecks::DealingDate::InstructionsSent
    WorkflowChecks::DealingDate::CollectMoneyAfter
    WorkflowChecks::DealingDate::Allotted
    WorkflowChecks::DealingDate::RedemptionsPaid
    WorkflowChecks::DealingDate::UnitsCancelled
    WorkflowChecks::DealingDate::DocumentsGenerated
    WorkflowChecks::DealingDate::DocumentsSent
    WorkflowChecks::DealingDate::Closed
    WorkflowChecks::DealingDate::NotPreFunded
    WorkflowChecks::DealingDate::NotPayAfter
    WorkflowChecks::DealingDate::NoSubscriptions
    WorkflowChecks::DealingDate::NoRedemptions
    WorkflowChecks::DealingDate::NoDocumentTemplates
  ]
  check_classes.each { |name| WorkflowChecks::Registry.register(name.constantize) }
end
