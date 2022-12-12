class ElasticImporterJob < ApplicationJob
  queue_as :default

  def perform(*_args)
    UserIndex.import
    EntityIndex.import
    InvestmentIndex.import
    AccessRightIndex.import
    DealInvestorIndex.import
    DocumentIndex.import
    HoldingIndex.import
    InvestorIndex.import
    InvestorAccessIndex.import
    NoteIndex.import
    SecondarySaleIndex.import
    HoldingAuditTrailIndex.import
    ExcerciseIndex.import
    OfferIndex.import
    TaskIndex.import
    InvestmentOpportunityIndex.import
    FundIndex.import
    CapitalCommitmentIndex.import
    CapitalRemittanceIndex.import
    CapitalDistributionPaymentIndex.import
    InvestorKycIndex.import
  end

  def reset
    UserIndex.reset!
    EntityIndex.reset!
    InvestmentIndex.reset!
    AccessRightIndex.reset!
    DealInvestorIndex.reset!
    DocumentIndex.reset!
    HoldingIndex.reset!
    InvestorIndex.reset!
    InvestorAccessIndex.reset!
    NoteIndex.reset!
    SecondarySaleIndex.reset!
    HoldingAuditTrailIndex.reset!
    ExcerciseIndex.reset!
    OfferIndex.reset!
    TaskIndex.reset!
    InvestmentOpportunityIndex.reset!
    FundIndex.reset!
    CapitalCommitmentIndex.reset!
    CapitalRemittanceIndex.reset!
    CapitalDistributionPaymentIndex.reset!
    InvestorKycIndex.reset!
  end

  def create
    UserIndex.create
    EntityIndex.create
    InvestmentIndex.create
    AccessRightIndex.create
    DealInvestorIndex.create
    DocumentIndex.create
    HoldingIndex.create
    InvestorIndex.create
    InvestorAccessIndex.create
    NoteIndex.create
    SecondarySaleIndex.create
    HoldingAuditTrailIndex.create
    ExcerciseIndex.create
    OfferIndex.create
    TaskIndex.create
    InvestmentOpportunityIndex.create
    FundIndex.create
    CapitalCommitmentIndex.create
    CapitalRemittanceIndex.create
    CapitalDistributionPaymentIndex.create
    InvestorKycIndex.create
  end
end
