class ImportFundUnitSettingService < ImportServiceBase
  step :read_file
  step Subprocess(ImportFundUnitSetting)
  step :save_results_file
end
