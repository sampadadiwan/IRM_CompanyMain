class AccessRightSearch
  def self.search(access_rights, params, current_user)
    owner = nil

    if params[:owner_type].present? && params[:owner_id].present?
      # Search in fund provided user is authorized
      owner = params[:owner_type].constantize.find(params[:owner_id])
    else
      # Search in users entity only
      term = { entity_id: current_user.entity_id }
    end

    search_value = params[:search] && params[:search][:value]

    if search_value.present?
      # This is only when the datatable sends a search query
      query = "#{SearchHelper.sanitize_text_for_search(search_value)}*"

      # Increase limit to avoid cutting off search results before strict pagination
      limit = 1000

      chewy_query = if owner
                      AccessRightIndex.filter(term: { owner_id: owner.id })
                                      .query(match: { owner_type: params[:owner_type] })
                    else
                      AccessRightIndex.filter(term:)
                    end

      chewy_query = chewy_query.query(simple_query_string: { fields: AccessRightIndex::SEARCH_FIELDS,
                                                             query:, default_operator: 'and' })

      ids = chewy_query.per(limit).map(&:id)
      access_rights = access_rights.where(id: ids)
    end
    access_rights
  end
end
