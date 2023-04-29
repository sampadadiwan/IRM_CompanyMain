class AddDataRoomToFund < ActiveRecord::Migration[7.0]
  def change
    add_reference :funds, :data_room_folder, null: true, foreign_key: {to_table: :folders}        
  end
end
