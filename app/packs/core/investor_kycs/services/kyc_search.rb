class KycSearch
  def self.perform(investor_kycs, current_user, params)
    investor_kycs = investor_kycs.where(id: search_ids(params, current_user)) if params[:search] && params[:search][:value].present?
    investor_kycs = investor_kycs.where(investor_id: params[:investor_id]) if params[:investor_id]
    investor_kycs = investor_kycs.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id]

    investor_kycs = investor_kycs.where(verified: params[:verified] == "true") if params[:verified].present?
    investor_kycs = investor_kycs.where(expiry_date: ..Time.zone.today) if params[:expired].present?

    investor_kycs = investor_kycs.where(kyc_type: params[:kyc_type]) if params[:kyc_type].present?

    investor_kycs = investor_kycs.includes(:investor, :entity)
    # The distinct clause is there because IAs can access only KYCs that belong to thier funds
    # See policy_scope - this query returns dups
    investor_kycs.distinct
  end

  def self.search_ids(params, current_user)
    # This is only when the datatable sends a search query
    query = "#{params[:search][:value]}*"
    entity_ids = [current_user.entity_id]
    InvestorKycIndex.filter(terms: { entity_id: entity_ids })
                    .query(query_string: { fields: InvestorKycIndex::SEARCH_FIELDS,
                                           query:, default_operator: 'and' }).per(100).map(&:id)
  end
end
