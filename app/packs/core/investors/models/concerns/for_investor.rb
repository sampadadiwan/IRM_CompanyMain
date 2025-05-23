module ForInvestor
  extend ActiveSupport::Concern

  included do
    # Defines which tabel to join with for access_rights
    def self.parent_class_type
      if %w[CapitalCommitment CapitalRemittance CapitalRemittancePayment CapitalDistribution CapitalCall CapitalDistributionPayment FundUnit FundRatio FundUnit FundUnitSetting PortfolioInvestment AggregatePortfolioInvestment FundFormula FundReport PortfolioScenario CommitmentAdjustment AccountEntry].include?(name)
        Fund
      elsif ["ExpressionOfInterest"].include?(name)
        InvestmentOpportunity
      elsif %w[Offer Interest Allocation].include?(name)
        SecondarySale
      elsif %w[Kpi].include?(name)
        KpiReport
      elsif %w[DealInvestor].include?(name)
        Deal
      else
        self
      end
    end

    scope :for_company_admin, lambda { |user|
      table_name = parent_class_type.name.underscore.pluralize
      join_clause = if parent_class_type.name == name
                      joins(:entity)
                    else
                      joins(parent_class_type.name.underscore.to_sym)
                    end

      if user.entity_type == "Group Company"
        join_clause.where("#{table_name}": { entity_id: user.entity.child_ids })
      else
        join_clause.where("#{table_name}": { entity_id: user.entity_id })
      end
    }

    scope :for_employee, lambda { |user|
      table_name = parent_class_type.name.underscore.pluralize
      join_clause = if parent_class_type.name == name
                      joins(:entity)
                    else
                      joins(parent_class_type.name.underscore.to_sym)
                    end

      # This is the list of ids for which the user has been granted specific access
      cached_ids = user.get_cached_ids(user.entity_id, parent_class_type.name)

      if user.entity_type == "Group Company"
        join_clause.where("#{table_name}": { entity_id: user.entity.child_ids, id: cached_ids })
      else
        join_clause.where("#{table_name}": { entity_id: user.entity_id, id: cached_ids })
      end
    }

    scope :for_rm, lambda { |user|
      join_clause = if instance_methods.include?(:access_rights)
                      Rails.logger.debug { "######## for_rm has access_rights" }
                      if instance_methods.include?(:investor)
                        Rails.logger.debug { "######## for_rm 1 has :investor" }
                        joins(:access_rights).joins(investor: :rm_mappings)
                      else
                        # This is for the case where the model has access_rights like SecondarySale, Fund, Deal, Approval etc
                        Rails.logger.debug { "######## for_rm 2 joins entity: :investor" }
                        joins(:access_rights).joins(entity: :investors)
                      end
                    elsif instance_methods.include?(:investor)
                      Rails.logger.debug { "######## for_rm 3 joins investor: :rm_mappings" }
                      joins(investor: :rm_mappings).joins(parent_class_type.name.underscore => :access_rights)
                    else
                      Rails.logger.debug { "######## for_rm 4" }
                      joins(parent_class_type.name.underscore => :access_rights).joins(entity: :investors)
                    end

      # Filter by access rights
      join_clause = if instance_methods.include?(:investor)
                      # These are models like offers, interests, commitments etc which have an investor association, and have the access rights which are given in the parent model to the RM. So special treament to join with the rm_mappings table instead of the investors table
                      filter = AccessRight.access_filter_for_rm(user)
                      join_clause.merge(filter).where("rm_mappings.rm_entity_id=?", user.entity_id)
                    else
                      # These are models like secondary_sale, deal, fund, approval etc which dont have an investor association, and have the access rights which are given to the RM. So we treat it like  aregular investor access
                      filter = AccessRight.access_filter(user)
                      join_clause.merge(filter).where("investors.investor_entity_id=?", user.entity_id)
                    end

      # Ensure the investor access is approved
      join_clause = join_clause.joins(entity: :investor_accesses).merge(InvestorAccess.approved_for_user(user))

      if self.respond_to?(:user_id) && !user.has_cached_role?(:company_admin)
        join_clause = join_clause.where("#{self.table_name}.user_id" => user.id) 
      end

      join_clause
    }

    # Some models have a belongs_to :investor association
    scope :for_investor, lambda { |user|
      filter = user.investor_advisor? ? AccessRight.investor_granted_access_filter(user) : AccessRight.access_filter(user)

      join_clause = if instance_methods.include?(:access_rights)
                      Rails.logger.debug { "######## for_investor has access_rights" }
                      if instance_methods.include?(:investor)
                        Rails.logger.debug { "######## for_investor has :investor" }
                        joins(:access_rights).joins(:investor)
                      else
                        Rails.logger.debug { "######## for_investor has entity: :investor" }
                        joins(:access_rights).joins(entity: :investors)
                      end
                    elsif instance_methods.include?(:investor)
                      Rails.logger.debug { "######## for_investor has :investor" }
                      joins(:investor, parent_class_type.name.underscore => :access_rights)
                    else
                      Rails.logger.debug { "######## for_investor has parent_class_type #{parent_class_type}" }
                      joins(parent_class_type.name.underscore => :access_rights).joins(entity: :investors)
                    end
      # Need to join the parent mode with access_rights as the parent (Fund, IO, SecondarySale) has the access rights

      Rails.logger.debug join_clause.to_sql

      join_clause = join_clause.merge(filter)
                               .where("investors.investor_entity_id=?", user.entity_id)

      # Ensure the investor access is approved
      join_clause = join_clause.joins(entity: :investor_accesses).merge(InvestorAccess.approved_for_user(user))

      join_clause
    }
  end

  def model_with_access_rights
    if %w[CapitalCommitment CapitalRemittance CapitalRemittancePayment CapitalDistribution CapitalCall CapitalDistributionPayment FundUnit FundRatio FundUnit FundUnitSetting PortfolioInvestment AggregatePortfolioInvestment FundFormula FundReport PortfolioScenario CommitmentAdjustment AccountEntry].include?(self.class.name)
      fund
    elsif %w[ExpressionOfInterest].include?(self.class.name)
      investment_opportunity
    elsif %w[Offer Interest Allocation].include?(self.class.name)
      secondary_sale
    elsif %w[ApprovalResponse].include?(self.class.name)
      approval
    elsif %w[Kpi].include?(self.class.name)
      kpi_report
    elsif %w[DealInvestor].include?(self.class.name)
      deal
    else
      self
    end
  end
end
