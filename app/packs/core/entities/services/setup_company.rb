class SetupCompany < Trailblazer::Operation
  step :setup_folders

  # rubocop:disable Rails/SkipsModelValidations
  def setup_folders(_ctx, entity:, **)
    if entity.root_folder.blank?
      entity.update_column(:root_folder_id, Folder.create(name: "/", entity_id: entity.id, level: 0, folder_type: :regular).id)
      entity.reload
    end
    true
  end
  # rubocop:enable Rails/SkipsModelValidations
end
