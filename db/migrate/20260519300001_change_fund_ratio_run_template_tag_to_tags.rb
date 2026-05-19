class ChangeFundRatioRunTemplateTagToTags < ActiveRecord::Migration[8.1]
  def change
    # Drop the old single-value index and column.
    remove_index  :fund_ratio_run_templates, %i[entity_id tag]
    remove_column :fund_ratio_run_templates, :tag, :string

    # tags is a JSON array — no DB default (MySQL rejects literal defaults on JSON).
    # The model declares `attribute :tags, :json, default: -> { [] }`.
    add_column :fund_ratio_run_templates, :tags, :json, null: false
  end
end
