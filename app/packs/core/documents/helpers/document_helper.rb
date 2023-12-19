module DocumentHelper
  FIXNUM_MAX = ((2**((0.size * 8) - 2)) - 1)

  # This method returns all the folders to be displayed in the tree view
  def get_tree_view_folders(params, current_user, entity, documents)
    entity_id = params[:entity_id].present? ? params[:entity_id].to_i : current_user.entity_id

    # If the user is from the same company show him all the folders
    if belongs_to_entity_id?(current_user, entity_id) && current_user.has_cached_role?(:company_admin)
      folders = if params[:folder_id].present?
                  Folder.find(params[:folder_id]).subtree.order(:name).arrange
                else
                  entity.root_folder.subtree.order(:name).arrange
                end
    else
      # If the user is NOT from the same company show him only the folders for the documents he has access to

      aids = with_ancestor_ids(documents)

      if params[:folder_id].present?
        # We need to show only the descendants of parent, but we also want to show only those folder for which the user has documents that he can see.
        parent = Folder.find(params[:folder_id])
        # descendant_ids = parent.descendant_ids
        # descendant_ids << parent.id
        # folders = Folder.where(id: descendant_ids).where(id: aids).order(:name).arrange
        folders = Folder.where("level >= ?", parent.level).where(id: aids).order(:name).arrange
      else
        folders = Folder.where(id: aids).order(:name).arrange
      end
    end

    folders
  end

  def with_ancestor_ids(documents)
    ids = documents.joins(:folder).pluck("documents.folder_id, folders.ancestry")
    ids.map { |p| p[1] ? (p[1].split("/") << p[0]) : [p[0]] }.flatten.map(&:to_i).uniq
  end

  def update_signature_progress(params)
    if params.dig('payload', 'document', 'id').present? && params.dig('payload', 'document', 'error_code').blank?
      doc = Document.find_by(provider_doc_id: params.dig('payload', 'document', 'id'))
      params['payload']['document']['signing_parties'].each do |signer|
        user = User.find_by(email: signer['identifier'])
        if user
          esign = doc&.e_signatures&.find_by(user_id: user.id)
          # callbacks can be out of order leading to multiple updates for the same status
          if esign.present? && (esign.status != signer['status'] && esign.status != "signed")
            esign.add_api_update(params['payload'])
            esign.update(status: signer['status'], api_updates: esign.api_updates)
            message = "Document - #{doc.name}'s E-Sign status updated"
            logger.info message
            UserAlert.new(user_id: user.id, message:, level: "info").broadcast
            check_and_update_document_status(doc)
          elsif esign.blank?
            e = StandardError.new("E-Sign not found for #{doc&.name} and user #{user&.name} - #{params}")
            ExceptionNotifier.notify_exception(e)
            logger.error e.message
            # raise e
          else
            e = StandardError.new("E-Sign already has status #{esign&.status} for #{doc&.name} and user #{user&.name} - #{params}")
            # ExceptionNotifier.notify_exception(e)
            logger.error e.message
            # raise e
          end
        else
          e = StandardError.new("User not found for #{doc&.name} with identifier #{signer['identifier']} - #{params}")
          ExceptionNotifier.notify_exception(e)
          logger.error e.message
          # raise e
        end
      end
    elsif params.dig('payload', 'document', 'error_code').present?
      email = params.dig('payload', 'document', 'signer_identifier')
      user = User.find_by(email:)
      if user
        doc = Document.find_by(provider_doc_id: params.dig('payload', 'document', 'id'))
        esign = doc&.e_signatures&.find_by(user_id: user.id)
        if esign.present? && esign.status != "signed" && esign.status != "failed"
          esign.add_api_update(params['payload'])
          esign.update(status: "failed", api_updates: esign.api_updates)
          message = "Document - #{doc.name}'s E-Sign status updated"
          logger.info message
          UserAlert.new(user_id: user.id, message:, level: "info").broadcast
          check_and_update_document_status(doc)
        else
          e = StandardError.new("E-Sign not found or already updated for #{doc&.name} and user #{user&.name} - #{params}")
          ExceptionNotifier.notify_exception(e)
          logger.error e.message
          # raise e
        end
      else
        e = StandardError.new("User not found for #{doc&.name} with identifier #{signer['identifier']} - #{params}")
        ExceptionNotifier.notify_exception(e)
        logger.error e.message
        # raise e
      end
    end
  end

  def check_and_update_document_status(doc)
    unsigned_esigns = doc.e_signatures.reload.where.not(status: "signed")
    EsignUpdateJob.new.signature_completed(doc) if unsigned_esigns.count < 1
  end
end
