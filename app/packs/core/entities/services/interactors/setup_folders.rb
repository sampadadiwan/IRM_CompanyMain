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
    root = entity.root_folder.presence ||
           Folder.create(name: "/", entity_id: entity.id, level: 0, folder_type: :system)
    case entity.entity_type
    when "Startup"
      create_if_not_exist("Deals", entity, root, :system)
      create_if_not_exist("Approvals", entity, root, :system)
      create_if_not_exist("Secondary Sales", entity, root, :system)
      create_if_not_exist("Option Pools", entity, root, :system)
    when "Investment Fund"
      create_if_not_exist("Investment Opportunities", entity, root, :system)
      create_if_not_exist("Funds", entity, root, :system)
      create_if_not_exist("Approvals", entity, root, :system)
    end
  end

  def create_if_not_exist(name, entity, parent, folder_type)
    existing = Folder.where(name:, entity_id: entity.id, parent_folder_id: parent.id, folder_type:).first
    Folder.create(name:, entity_id: entity.id, parent_folder_id: parent.id, folder_type:) unless existing
  end
end
