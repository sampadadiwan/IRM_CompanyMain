class ElasticImporterJob < ApplicationJob
  queue_as :default

  def perform(*_args)
    UserIndex.import
    EntityIndex.import
    InvestmentIndex.import
    AccessRightIndex.import
    DealInvestorIndex.import
    DocumentIndex.import
    InvestorIndex.import
    InvestorAccessIndex.import
    NoteIndex.import
    SecondarySaleIndex.import
    CapitalCallIndex.import
    OfferIndex.import
    TaskIndex.import
    InvestmentOpportunityIndex.import
    FundIndex.import
    CapitalCommitmentIndex.import
    CapitalRemittanceIndex.import
    CapitalDistributionPaymentIndex.import
    InvestorKycIndex.import
    KanbanCardIndex.import
    AggregatePortfolioInvestmentIndex.import
    PortfolioInvestmentIndex.import
    KpiReportIndex.import
    FundFormulaIndex.import
  end

  def reset
    UserIndex.reset!
    EntityIndex.reset!
    # InvestmentIndex.reset!
    AccessRightIndex.reset!
    DealInvestorIndex.reset!
    DocumentIndex.reset!
    InvestorIndex.reset!
    InvestorAccessIndex.reset!
    NoteIndex.reset!
    SecondarySaleIndex.reset!
    CapitalCallIndex.reset!
    OfferIndex.reset!
    TaskIndex.reset!
    InvestmentOpportunityIndex.reset!
    FundIndex.reset!
    CapitalCommitmentIndex.reset!
    CapitalRemittanceIndex.reset!
    CapitalDistributionPaymentIndex.reset!
    InvestorKycIndex.reset!
    KanbanCardIndex.reset!
    AggregatePortfolioInvestmentIndex.reset!
    PortfolioInvestmentIndex.reset!
    KpiReportIndex.reset!
    FundFormulaIndex.reset!
  end

  def create
    UserIndex.create
    EntityIndex.create
    InvestmentIndex.create
    AccessRightIndex.create
    DealInvestorIndex.create
    DocumentIndex.create
    InvestorIndex.create
    InvestorAccessIndex.create
    NoteIndex.create
    SecondarySaleIndex.create
    CapitalCallIndex.create
    OfferIndex.create
    TaskIndex.create
    InvestmentOpportunityIndex.create
    FundIndex.create
    CapitalCommitmentIndex.create
    CapitalRemittanceIndex.create
    CapitalDistributionPaymentIndex.create
    InvestorKycIndex.create
    KanbanCardIndex.create
    AggregatePortfolioInvestmentIndex.create
    PortfolioInvestmentIndex.create
    KpiReportIndex.create
    FundFormulaIndex.create
  end
end
