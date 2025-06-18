class SetupCompany < Trailblazer::Operation
  step :setup_folders

  def setup_folders(_ctx, entity:, **)
    if entity.root_folder.blank?
      entity.update_column(:root_folder_id, Folder.create(name: "/", entity_id: entity.id, level: 0, folder_type: :regular).id)
      entity.reload
    end
    true
  end
end
