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
  end

  def reset
    UserIndex.reset
    EntityIndex.reset
    InvestmentIndex.reset
    AccessRightIndex.reset
    DealInvestorIndex.reset
    DocumentIndex.reset
    HoldingIndex.reset
    InvestorIndex.reset
    InvestorAccessIndex.reset
    NoteIndex.reset
    SecondarySaleIndex.reset
    HoldingAuditTrailIndex.reset
    ExcerciseIndex.reset
    OfferIndex.reset
  end
end
