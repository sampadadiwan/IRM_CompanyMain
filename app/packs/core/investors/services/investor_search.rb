class InvestorSearch
  def self.search(investors, params, current_user)
    investors = investors.where(category: params[:category]) if params[:category].present?
    investors = investors.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
    investors = investors.not_interacted(params[:not_interacted].to_i) if params[:not_interacted].present?
    investors = investors.where(category: params[:categories].split(",").map(&:strip)) if params[:categories].present?

    if params[:owner_id].present? && params[:owner_type].present?
      # L14 — an owner whose access rights list its investors (Fund, InvestmentOpportunity, …); an
      # unknown name is a 404, not a 500 (L14-5)
      owner_class = ApplicationRecord.model_class_from_param(params[:owner_type], allowed: AccessRightSearch::OWNER_TYPES)
      raise ActiveRecord::RecordNotFound, "Unknown owner type" unless owner_class

      owner = owner_class.find(params[:owner_id])
      policy_class = "#{owner.class.name}Policy".constantize
      investors = if policy_class.new(current_user, owner).show?
                    owner.investors
                  else
                    Investor.none
                  end
      # elsif !current_user.has_cached_role?(:company_admin)
      #   # No owner, he must be company admin or employee with investor access, else show nothing
      #   investors = investors.for_employee(current_user)
    end

    if params[:search] && params[:search][:value].present?
      # This is only when the datatable sends a search query
      # If we have @ then its an email, so dont wildcard it
      query = params[:search][:value].index("@") ? params[:search][:value] : "#{SearchHelper.sanitize_text_for_search(params[:search][:value])}*"

      ids = InvestorIndex.filter(term: { entity_id: current_user.entity_id })
                         .query(simple_query_string: { fields: InvestorIndex::SEARCH_FIELDS,
                                                       query:, default_operator: 'and' }).per(100).map(&:id)

      investors = investors.where(id: ids)
    end

    if params[:perm].present?
      investors = investors.perms(params[:perm])
    elsif params[:no_perm].present?
      investors = investors.no_perms(params[:no_perm])
    end

    investors.joins(:entity, :investor_entity)
  end
end
