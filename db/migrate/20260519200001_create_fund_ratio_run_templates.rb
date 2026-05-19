class CreateFundRatioRunTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :fund_ratio_run_templates do |t|
      # Every template belongs to one entity — the entity's collection of templates
      # is the implicit "set". No separate set wrapper table is needed.
      t.references :entity,      null: false, foreign_key: true
      t.references :user,        null: false, foreign_key: true
      # anchor_fund is used for document folder resolution and policy scoping,
      # matching the semantics of FundRatioRun#anchor_fund.
      t.references :anchor_fund, null: true,  foreign_key: { to_table: :funds }

      # Human label — must be unique within the entity so users can identify runs.
      t.string :name, null: false

      # Free-text grouping label. Multiple templates share the same tag to form
      # a logical group that can be triggered together ("Run by Tag").
      t.string :tag

      # "cross-fund" or "cross-portfolio" — mirrors FundRatioRun#run_type.
      t.string :run_type, null: false

      # Filter fields — identical semantics to FundRatioRun's stored inputs.
      # Defaults prevent nil; the model declares attribute defaults for new records.
      # No DB-level default on JSON columns — MySQL rejects that. Defaults are
      # declared in the model via `attribute :field, :json, default: -> { [] }`.
      t.json   :fund_ids,              null: false
      t.json   :portfolio_company_ids, null: false
      t.string :portfolio_companies_tags
      t.json   :sectors,               null: false

      # Nil means "use entity currency at job-dispatch time", same as FundRatiosScenarioJob.
      t.string :currency

      # Controls display order in the index UI.
      t.integer :position

      t.timestamps
    end

    # Enforce unique names within an entity so users can't create duplicate templates.
    add_index :fund_ratio_run_templates, %i[entity_id name], unique: true
    # Tag index supports the "run by tag" query: WHERE entity_id = ? AND tag = ?
    add_index :fund_ratio_run_templates, %i[entity_id tag]
  end
end
