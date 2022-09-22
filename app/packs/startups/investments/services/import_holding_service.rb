class ImportHoldingService
  include Interactor::Organizer

  organize ImportPreProcess, ImportHolding, ImportPostProcess
end
