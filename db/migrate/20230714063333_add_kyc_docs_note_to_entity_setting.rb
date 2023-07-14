class AddKycDocsNoteToEntitySetting < ActiveRecord::Migration[7.0]
  def change
    add_column :entity_settings, :kyc_docs_note, :text
  end
end
