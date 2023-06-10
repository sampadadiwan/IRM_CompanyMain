module DocumentHelper
  FIXNUM_MAX = ((2**((0.size * 8) - 2)) - 1)

  # This method returns all the folders to be displayed in the tree view
  def get_tree_view_folders(params, current_user, entity, documents)
    entity_id = params[:entity_id].present? ? params[:entity_id].to_i : current_user.entity_id

    # If the user is from the same company show him all the folders
    if entity_id == current_user.entity_id
      folders = if params[:folder_id].present?
                  Folder.find(params[:folder_id]).subtree.order(:name).arrange
                else
                  entity.root_folder.subtree.order(:name).arrange
                end
    else
      # If the user is NOT from the same company show him only the folders for the documents he has access to

      # Documents are paginated, but we want to show folders for all documents
      # This is to ensure pagination does not cause folders to not show up in the tree view
      aids = with_ancestor_ids(documents.per(FIXNUM_MAX))

      if params[:folder_id].present?
        # We need to show only the descendants of parent, but we also want to show only those folder for which the user has documents that he can see.
        parent = Folder.find(params[:folder_id])
        descendant_ids = parent.descendant_ids
        descendant_ids << parent.id
        folders = Folder.where(id: descendant_ids).where(id: aids).order(:name).arrange
      else
        folders = Folder.where(id: aids).order(:name).arrange
      end
    end

    folders
  end

  def with_ancestor_ids(documents)
    ids = documents.joins(:folder).pluck("documents.folder_id, folders.ancestry")
    ids.map { |p| p[1] ? (p[1].split("/") << p[0]) : [p[0]] }.flatten.map(&:to_i)
  end
end
