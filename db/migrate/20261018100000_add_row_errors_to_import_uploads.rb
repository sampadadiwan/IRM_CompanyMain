# The first failed rows of an import (row number + message), so an API client can see why rows
# failed without downloading and opening the results file.
# openspec/changes/funds-json-api-hardening — phase 8, P1 (Orios trial). Worked examples H20 H21 E26.
class AddRowErrorsToImportUploads < ActiveRecord::Migration[8.1]
  def change
    add_column :import_uploads, :row_errors, :json
  end
end
