class ImportCapitalRemittancePaymentService
  include Interactor::Organizer

  organize ImportPreProcess, ImportCapitalRemittancePayment, ImportPostProcess
end
