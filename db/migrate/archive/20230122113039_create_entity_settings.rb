class CreateEntitySettings < ActiveRecord::Migration[7.0]
  def change
    create_table :entity_settings do |t|
      t.boolean :pan_verification
      t.boolean :bank_verification
      t.boolean :trial
      t.date :trial_end_date
      t.string :valuation_math
      t.integer :snapshot_frequency_months
      t.date :last_snapshot_on
      t.references :entity, null: false, foreign_key: true

      t.timestamps
    end

    Entity.all.each do |e|
      EntitySetting.create!(entity: e, trial: e.trial, trial_end_date: e.trial_end_date, valuation_math: e.valuation_math, snapshot_frequency_months: e.snapshot_frequency_months, last_snapshot_on: e.last_snapshot_on)
    end

    remove_column :entities, :trial
    remove_column :entities, :trial_end_date
    remove_column :entities, :valuation_math
    remove_column :entities, :snapshot_frequency_months
    remove_column :entities, :last_snapshot_on
  end
end
