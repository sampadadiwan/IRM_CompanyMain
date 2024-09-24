class CreateBoardsForExisitingDeals < ActiveRecord::Migration[7.1]
  def change
    Deal.all.each do |deal|
      begin
        deal.create_kanban_board
      rescue StandardError => e
        next
      end
    end
    
    DealInvestor.all.each do |deal_investor|
      begin
        deal_investor.create_or_update_kanban_card
      rescue StandardError => e
        next
      end
    end
    
  end
end
