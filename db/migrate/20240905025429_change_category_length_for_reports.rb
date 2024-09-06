class ChangeCategoryLengthForReports < ActiveRecord::Migration[7.1]
  def change
    change_column :reports, :category, :string, limit: 50
  end
end
