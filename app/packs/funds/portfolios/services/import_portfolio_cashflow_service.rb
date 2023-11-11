class ImportPortfolioCashflowService
  include Interactor::Organizer

  organize ImportPreProcess, ImportPortfolioCashflow, ImportPostProcess
end
