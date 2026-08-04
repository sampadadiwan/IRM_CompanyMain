# DealManagementAgent's investor scoring writes each active investor's AI score
# back to their DealInvestor row (guarded by a column-existence check until now).
# ai_score is the 0–100 overall score; ai_grade is a short letter grade ("B+"),
# capped at 10 chars to match the agent's write-back truncation.
class AddAiScoreToDealInvestors < ActiveRecord::Migration[8.1]
  def change
    add_column :deal_investors, :ai_score, :integer unless column_exists?(:deal_investors, :ai_score)
    add_column :deal_investors, :ai_grade, :string, limit: 10 unless column_exists?(:deal_investors, :ai_grade)
  end
end
