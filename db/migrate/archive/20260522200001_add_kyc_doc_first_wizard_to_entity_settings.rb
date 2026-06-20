class AddKycDocFirstWizardToEntitySettings < ActiveRecord::Migration[7.1]
  def change
    add_column :entity_settings, :kyc_doc_first_wizard, :boolean, default: false, null: false
  end
end
