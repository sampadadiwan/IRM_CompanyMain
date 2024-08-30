class AddDetailsTopToCiWidget < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:ci_widgets, :details_top)
      add_column :ci_widgets, :details_top, :text
    end
  end
end
