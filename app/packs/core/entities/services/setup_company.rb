class SetupCompany < Trailblazer::Operation
  step :setup_folders

  def setup_folders(_ctx, entity:, **)
    entity.root_folder.presence ||
      Folder.create(name: "/", entity_id: entity.id, level: 0, folder_type: :regular)
  end
end
