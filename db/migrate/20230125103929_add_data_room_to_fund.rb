class AddDataRoomToFund < ActiveRecord::Migration[7.0]
  def change
    add_reference :funds, :data_room_folder, null: true, foreign_key: {to_table: :folders}
    # Ensure all funds have data rooms and they have access rights
    Fund.all.each do |f|
      f.create_data_room
      f.access_rights.each do |ar|
        f.data_room_folder.access_rights_changed(ar)
      end
    end

    # Ensure all funds folders are now made regular
    Entity.all.each do |e|
      e.folders.where(name: "Funds").each do |df|
        df.folder_type = :regular
        df.save

        df.children.each do |c|
          c.folder_type = :regular
          c.save
        end
      end
    end
  end
end
