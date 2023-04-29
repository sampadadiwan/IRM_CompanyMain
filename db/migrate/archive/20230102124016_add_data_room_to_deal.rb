class AddDataRoomToDeal < ActiveRecord::Migration[7.0]
  def change
    add_reference :deals, :data_room_folder, null: true, foreign_key: {to_table: :folders}
    Deal.all.each(&:create_data_room)
    Entity.all.each do |e|
      e.folders.where(name: "Deals").each do |df|
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
