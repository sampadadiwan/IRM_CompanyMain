class UpdateInvestorSebiInfos < ActiveRecord::Migration[7.1]
  def up
    # remove investor sebi infos if present
    if table_exists?(:investor_sebi_infos)
      # drop_table :investor_sebi_infos
    end

    # create investor kyc sebi datas
    if !table_exists?(:investor_kyc_sebi_datas)
      create_table :investor_kyc_sebi_datas do |t|

        t.string :investor_category
        t.string :investor_sub_category

        t.references :investor_kyc, null: false, foreign_key: true
        t.references :entity, null: false, foreign_key: true
        t.timestamps
      end
    end
  end

  def down
    # remove investor kyc sebi datas if present
    if table_exists?(:investor_kyc_sebi_datas)
      drop_table :investor_kyc_sebi_datas
    end
  end
end
