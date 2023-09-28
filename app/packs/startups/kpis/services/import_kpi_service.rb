class ImportKpiService
  include Interactor::Organizer

  organize ImportPreProcess, ImportKpi, ImportPostProcess
end
