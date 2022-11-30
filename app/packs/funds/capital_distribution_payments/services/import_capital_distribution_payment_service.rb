class ImportCapitalDistributionPaymentService
  include Interactor::Organizer

  organize ImportPreProcess, ImportCapitalDistributionPayment, ImportPostProcess
end
