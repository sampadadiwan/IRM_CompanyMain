class ImportFundUnitSettingService
  include Interactor::Organizer

  organize ImportPreProcess, ImportFundUnitSetting, ImportPostProcess
end
