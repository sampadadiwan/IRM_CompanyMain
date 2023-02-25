module WithDataRoom
  extend ActiveSupport::Concern

  included do
    belongs_to :data_room_folder, class_name: "Folder", dependent: :destroy, optional: true
    after_create_commit :create_data_room
  end

  def create_data_room
    self.data_room_folder ||= document_folder.children.where(entity_id:, name: data_room_name, folder_type: :regular, owner: self).first_or_create
    save
  end

  def data_room_name
    "Data Room"
  end

  def access_rights_changed(access_right)
    ar = AccessRight.where(id: access_right.id).first
    if ar && ar.entity_id == entity_id
      # Add this ar to the data room
      data_room_ar = ar.dup
      data_room_ar.owner = data_room_folder
      data_room_ar.cascade = true
      data_room_ar.save
    else
      # Remove this ar to the data room
      data_room_folder.access_rights.where(access_to_investor_id: access_right.access_to_investor_id, access_to_category: access_right.access_to_category, user_id: access_right.user_id).each(&:destroy)
    end
  end
end
