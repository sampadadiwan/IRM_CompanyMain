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
    root = Folder.create(name: "/", entity_id: entity.id, level: 0, folder_type: :system)
    case entity.entity_type
    when "Startup"
      Folder.create(name: "Deals", entity_id: entity.id, parent: root, folder_type: :system)
      Folder.create(name: "Approvals", entity_id: entity.id, parent: root, folder_type: :system)
      Folder.create(name: "Secondary Sales", entity_id: entity.id, parent: root, folder_type: :system)
      Folder.create(name: "Option Pools", entity_id: entity.id, parent: root, folder_type: :system)
    when "Investment Fund"
      Folder.create(name: "Investment Opportunities", entity_id: entity.id, parent: root, folder_type: :system)
      Folder.create(name: "Funds", entity_id: entity.id, parent: root, folder_type: :system)
    end
  end
end
