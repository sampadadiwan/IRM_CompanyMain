class AddCriteriaToInvestorNoticeItems < ActiveRecord::Migration[8.1]
  def change
    add_column :investor_notice_items, :criteria, :text
  end
end
