class DestroyKanbanCardsForDeletedDealInvestors < ActiveRecord::Migration[7.1]
  def change
    KanbanCard.where(id: [104, 107]).each(&:destroy)
  end
end
