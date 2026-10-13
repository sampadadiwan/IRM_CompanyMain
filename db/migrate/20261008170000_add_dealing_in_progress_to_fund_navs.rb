# Money received for orders not yet dealt, and the payout of dealt-but-unpaid redemptions, held as a
# NAV liability until units are issued / cancelled (decision 8 Oct 2026, worked examples E201–E204)
class AddDealingInProgressToFundNavs < ActiveRecord::Migration[8.1]
  def change
    add_column :fund_navs, :dealing_in_progress_cents, :decimal, precision: 20, scale: 2, default: 0, null: false
  end
end
