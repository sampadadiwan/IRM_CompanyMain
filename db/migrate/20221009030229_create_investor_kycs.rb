class CreateInvestorKycs < ActiveRecord::Migration[7.0]
  def change
    create_table :investor_kycs do |t|
      t.references :investor, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :form_type, null: true, foreign_key: true
      t.string :first_name, limit: 50
      t.string :middle_name, limit: 50
      t.string :last_name, limit: 50
      t.string :PAN, limit: 15
      t.text :address
      t.string :bank_account_number, limit: 40
      t.string :ifsc_code, limit: 20
      t.boolean :bank_verified, default: false
      t.text :bank_verification_response
      t.string :bank_verification_status
      t.text :signature_data
      t.text :pan_card_data
      t.boolean :pan_verified, default: false
      t.text :pan_verification_response
      t.string :pan_verification_status
      t.text :comments
      t.text :properties

      t.timestamps
    end

    Entity.all.each do |e|
      SetupFolders.call(entity: e)
    end

    Investor.all.each do |i|
      i.setup_folder_details
    end

  end
end
