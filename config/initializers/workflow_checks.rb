# Registers every workflow check class with WorkflowChecks::Registry. Checks are looked up by the
# key stored on a workflow step, so they must be registered before any evaluation runs. Wrapped in
# to_prepare so a code reload in development re-registers the reloaded classes.
#
# Capital call checks: app/packs/funds/capital_calls/workflow_checks/capital_call/.
# Capital distribution checks: app/packs/funds/capital_distributions/workflow_checks/capital_distribution/
# (Worked examples H2 — openspec/changes/archive/2026-10-02-capital-distribution-journey/design.md#worked-examples).
# Investor KYC checks: app/packs/core/investor_kycs/workflow_checks/investor_kyc/
# (Worked examples H2 — openspec/changes/investor-kyc-journey/design.md#worked-examples).
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
    WorkflowChecks::InvestorKyc::SendForm
    WorkflowChecks::InvestorKyc::Submit
    WorkflowChecks::InvestorKyc::UploadDocuments
    WorkflowChecks::InvestorKyc::ValidateDocuments
    WorkflowChecks::InvestorKyc::RunAml
    WorkflowChecks::InvestorKyc::ClearAmlMatch
    WorkflowChecks::InvestorKyc::ReviewKyc
    WorkflowChecks::InvestorKyc::Verify
    WorkflowChecks::InvestorKyc::FilledByFund
    WorkflowChecks::InvestorKyc::NoRequiredDocuments
    WorkflowChecks::InvestorKyc::AmlOff
    WorkflowChecks::InvestorKyc::NoAmlMatch
  ]
  check_classes.each { |name| WorkflowChecks::Registry.register(name.constantize) }
end
