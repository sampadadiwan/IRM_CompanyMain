class ImportCapitalCommittmentService
  include Interactor::Organizer

  organize ImportPreProcess, ImportCapitalCommittment, ImportPostProcess
end
