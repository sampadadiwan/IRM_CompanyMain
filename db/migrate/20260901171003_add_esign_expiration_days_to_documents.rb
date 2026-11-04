class AddEsignExpirationDaysToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :esign_expiration_days, :integer, if_not_exists: true
  end
end
