# Steps for features/fund/bulk_query_formula_import.feature (bulk-path-query-optimisation, phase 5).
# The import goes through the real pipeline (ImportUpload + ImportUploadJob), with a sheet written by
# FundFormulaAttributes.to_xlsx - the same writer run check suggestions use (run_check_suggestions_steps.rb).

# Existing formulas "Existing 1".."Existing N" at the given sequences
Given('the fund has formulas at sequences {string}') do |sequences|
  sequences.split(",").map(&:strip).each_with_index do |sequence, i|
    FactoryBot.create(:fund_formula, entity: @fund.entity, fund: @fund, name: "Existing #{i + 1}", sequence: sequence.to_i)
  end
end

# One sheet row per entry, named "New 1".."New N"; a blank entry leaves the Sequence cell empty (E7)
When('I import fund formulas at sequences {string}') do |sequences|
  # "".split returns [] - an empty string means one row with an empty Sequence cell
  cells = sequences.empty? ? [""] : sequences.split(",", -1)
  rows = cells.map(&:strip).each_with_index.map do |sequence, i|
    { name: "New #{i + 1}", formula: "1+1", rule_type: "GenerateAccountEntry", rule_for: "accounting",
      entry_type: "Test", enabled: true, sequence: sequence.presence }
  end
  path = Rails.root.join("tmp/bulk_query_formula_import_#{@fund.id}.xlsx")
  File.binwrite(path, FundFormulaAttributes.to_xlsx(rows))
  upload = ImportUpload.create!(entity: @fund.entity, owner: @fund, import_type: "FundFormula", name: "Formula import",
                                user_id: @user.id, import_file: File.open(path))
  ImportUploadJob.perform_now(upload.id)
  @formula_upload = upload.reload
ensure
  FileUtils.rm_f(path) if path
end

# The whole list in sequence order, as the Formulas page shows it
Then('the fund formulas in order should be {string}') do |expected|
  actual = @fund.fund_formulas.order(:sequence, :id).map { |f| "#{f.name}@#{f.sequence}" }.join(", ")
  expect(actual).to eq(expected)
end
