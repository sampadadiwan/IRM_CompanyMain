class InvestorSearch
  def self.search(investors, params, current_user)
    investors = investors.where(category: params[:category]) if params[:category].present?
    investors = investors.where(import_upload_id: params[:import_upload_id]) if params[:import_upload_id].present?
    investors = investors.not_interacted(params[:not_interacted].to_i) if params[:not_interacted].present?

    if params[:owner_id].present? && params[:owner_type].present?
      owner = params[:owner_type].constantize.find(params[:owner_id])
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
      query = "#{params[:search][:value]}*"

      ids = InvestorIndex.filter(term: { entity_id: current_user.entity_id })
                         .query(query_string: { fields: InvestorIndex::SEARCH_FIELDS,
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
