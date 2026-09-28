class UpdateDocumentFolderPathJob < ApplicationJob
  queue_as :serial

  # A folder-path repair is pure catch-up work: nothing about its inputs changes between
  # attempts, so a RecordInvalid fails identically on all 26 tries of Sidekiq's default
  # retry budget and sends 26 error emails each time. That is what turned a handful of
  # poisoned records into ~75 emails on 2026-09-25. Log once, drop the job, and let the
  # next edit re-enqueue it -- the folder tree is stale, not corrupt.
  discard_on ActiveRecord::RecordInvalid do |job, error|
    Rails.logger.error do
      "UpdateDocumentFolderPathJob discarded for #{job.arguments.inspect}: #{error.message}"
    end
  end

  def perform(class_name, owner_id)
    Chewy.strategy(:sidekiq) do
      model_class = class_name.constantize
      owner = model_class.find_by(id: owner_id)
      return unless owner

      folder = owner.document_folder
      return if folder.nil?

      expected_full_path = owner.folder_path
      return unless folder_needs_update?(folder, expected_full_path)

      # The destination may already be occupied by a duplicate this owner also owns. Renaming
      # onto it is what raises "Full path combination must be unique"; merge instead.
      folder = merge_into_twin(owner, folder, expected_full_path) || folder

      update_folder_and_descendants(folder, expected_full_path)
    end
  end

  private

  def folder_needs_update?(folder, expected_full_path)
    folder.name != expected_full_path.split("/").last || folder.full_path != expected_full_path
  end

  # Another folder with the same owner already sitting at the path we are about to move to.
  # Historically produced by WithFolder#setup_document_folder failing to persist
  # document_folder_id and creating a fresh folder on the next touch -- see
  # WithFolder#link_document_folder for the full story.
  def twin_at(folder, expected_full_path)
    Folder.where(entity_id: folder.entity_id,
                 owner_id: folder.owner_id,
                 owner_type: folder.owner_type,
                 full_path: expected_full_path)
          .where.not(id: folder.id)
          .first
  end

  # Fold `folder` into the twin that already holds the wanted path, and repoint the owner at
  # it. The twin wins because it is already named correctly, so nothing has to be renamed onto
  # an occupied path. Returns the survivor, or nil when there is no twin (the normal case).
  def merge_into_twin(owner, folder, expected_full_path)
    twin = twin_at(folder, expected_full_path)
    return nil if twin.nil?

    Rails.logger.warn do
      "Merging duplicate folder #{folder.id} (#{folder.full_path}) into #{twin.id} " \
        "(#{twin.full_path}) for #{folder.owner_type} #{folder.owner_id}"
    end

    ActiveRecord::Base.transaction do
      move_contents(folder, twin)
      # Repoint before destroying: `belongs_to :document_folder, dependent: :destroy` means a
      # stale pointer would be left aimed at a soft-deleted row.
      owner.update_column(:document_folder_id, twin.id)
      folder.reload.destroy
    end

    twin
  end

  # Move every document and child of `source` under `target`.
  def move_contents(source, target)
    source.documents.find_each { |document| document.update!(folder: target) }
    # to_a first: reparenting mutates the association, and ancestry rewrites rows underneath it.
    source.children.to_a.each { |child| merge_child_into(child, target) }
  end

  # Reparent `child` under `target`, unless `target` already has a folder of the same name --
  # in which case merge into that one recursively. A blind reparent there would create a
  # second folder with the same full_path under the same owner: exactly the duplicate this
  # job exists to clear.
  def merge_child_into(child, target)
    twin = target.children.find_by(name: child.name, entity_id: child.entity_id)

    return child.update!(parent: target) if twin.nil?

    move_contents(child, twin)
    child.reload.destroy
  end

  def update_folder_and_descendants(folder, expected_full_path)
    folder.assign_attributes(
      name: expected_full_path.split("/").last,
      full_path: expected_full_path
    )
    folder.set_defaults
    folder.save!

    update_descendants(folder)
  end

  def update_descendants(folder)
    folder.children.includes(:entity).find_each do |child|
      child.set_defaults
      child.save!
      update_descendants(child)
    end
  end
end
