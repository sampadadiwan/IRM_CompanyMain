class AddYouTubeToCiWidget < ActiveRecord::Migration[7.1]
  def change
    add_column :ci_widgets, :embed_script, :text
  end
end
