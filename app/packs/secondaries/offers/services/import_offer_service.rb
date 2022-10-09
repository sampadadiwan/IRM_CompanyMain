class ImportOfferService
  include Interactor::Organizer

  organize ImportPreProcess, ImportOffer, ImportPostProcess
end
