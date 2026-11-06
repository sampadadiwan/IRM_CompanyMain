# Compliance records use the app's Trackable module like every other audited model (R178), which turns on
# soft delete (acts_as_paranoid) — so each audited compliance table needs deleted_at. Nothing in the
# normal flows deletes these rows; soft delete brings them into the app's data-recovery screens.
class AddDeletedAtToComplianceRecords < ActiveRecord::Migration[8.1]
  TABLES = %i[compliance_duties compliance_entity_setups compliance_register_items
              compliance_requests document_signoffs document_facts].freeze

  def change
    TABLES.each do |table|
      add_column table, :deleted_at, :datetime
      add_index table, :deleted_at
    end
  end
end
