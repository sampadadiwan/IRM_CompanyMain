class AddDataRoomToSecondarySale < ActiveRecord::Migration[7.1]
  def up
    # add_reference :secondary_sales, :data_room_folder, null: true, foreign_key: {to_table: :folders}
    SecondarySale.all.each do |s|
      puts "Creating data room for Secondary Sale #{s.name}"
      s.create_data_room
      s.access_rights.each do |ar|
        s.access_rights_changed(ar)
      end
    end
  end

  def down
    remove_reference :secondary_sales, :data_room_folder, foreign_key: {to_table: :folders}
  end
end
