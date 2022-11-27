class SetupFolders
  include Interactor

  def call
    Rails.logger.debug "Interactor: SetupFolders called"
    if context.entity.present?
      setup_root_folder(context.entity)
    else
      Rails.logger.error "No Entity specified"
      context.fail!(message: "No Entity specified")
    end
  end

  def setup_root_folder(entity)
    entity.root_folder.presence ||
      Folder.create(name: "/", entity_id: entity.id, level: 0, folder_type: :system)
  end

  def create_if_not_exist(name, entity, parent, folder_type)
    existing = Folder.where(name:, entity_id: entity.id, parent_id: parent.id, folder_type:).first
    Folder.create(name:, entity_id: entity.id, parent_id: parent.id, folder_type:) unless existing
  end
end
