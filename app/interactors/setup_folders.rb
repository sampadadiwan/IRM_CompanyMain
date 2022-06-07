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
    Folder.create(name: "/", entity_id: entity.id, level: 0)
  end
end
