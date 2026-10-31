class AccessRightSearch
  # L14 — the models access rights hang off: the owner types stored in production plus the models
  # declaring has_many :access_rights, as: :owner. Also the owners InvestorSearch lists investors of
  # (ApplicationRecord#investors reads their access rights)
  OWNER_TYPES = %w[Approval Deal DealInvestor Document Entity Folder Fund InvestmentOpportunity Investor
                   KpiReport Nudge SecondarySale].freeze

  def self.search(access_rights, params, current_user)
    owner = nil

    if params[:owner_type].present? && params[:owner_id].present?
      # L14 — only an access-right owner type; an unknown name is a 404, not a 500 (L14-5)
      owner_class = ApplicationRecord.model_class_from_param(params[:owner_type], allowed: OWNER_TYPES)
      raise ActiveRecord::RecordNotFound, "Unknown owner type" unless owner_class

      # Search in fund provided user is authorized
      owner = owner_class.find(params[:owner_id])
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
