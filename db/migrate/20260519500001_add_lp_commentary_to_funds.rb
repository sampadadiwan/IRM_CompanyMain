class AddLpCommentaryToFunds < ActiveRecord::Migration[7.2]
  def change
    add_column :funds, :lp_commentary, :text
  end
end
