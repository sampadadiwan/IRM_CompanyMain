class AddDataRoomFolderToInvestmentOpportunity < ActiveRecord::Migration[8.0]
  def change
    add_reference :investment_opportunities, :data_room_folder, null: true, foreign_key: { to_table: :folders }
    add_column :expression_of_interests, :show_data_room, :boolean, default: false, null: false
  end
end
