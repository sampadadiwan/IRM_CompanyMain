class ImportCapitalDistributionService
  include Interactor::Organizer

  organize ImportPreProcess, ImportCapitalDistribution, ImportPostProcess
end
