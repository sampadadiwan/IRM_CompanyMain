class CreateKycData < ActiveRecord::Migration[7.0]
  def change
    create_table :kyc_data do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :investor_kyc, foreign_key: true
      t.string :source
      t.json :response

      t.timestamps
    end
  end
end
