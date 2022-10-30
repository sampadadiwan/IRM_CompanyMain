class AddVideoToInvestorKyc < ActiveRecord::Migration[7.0]
  def change
    add_column :investor_kycs, :video_data, :text
  end
end
