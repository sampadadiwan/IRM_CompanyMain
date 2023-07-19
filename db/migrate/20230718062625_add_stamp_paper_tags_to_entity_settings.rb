class AddStampPaperTagsToEntitySettings < ActiveRecord::Migration[7.0]
  def change
    add_column :entity_settings, :stamp_paper_tags, :string
  end
end
