module ForInvestor
  extend ActiveSupport::Concern

  included do
    # Defines which tabel to join with for access_rights
    def self.parent_class_type
      if %w[CapitalCommitment CapitalRemittance CapitalRemittancePayment CapitalDistribution CapitalCall CapitalDistributionPayment FundUnit FundRatio FundUnit FundUnitSetting PortfolioInvestment AggregatePortfolioInvestment FundFormula FundReport PortfolioScenario CommitmentAdjustment AccountEntry].include?(name)
        Fund
      elsif ["ExpressionOfInterest"].include?(name)
        InvestmentOpportunity
      elsif %w[Offer Interest].include?(name)
        SecondarySale
      elsif %w[Kpi].include?(name)
        KpiReport
      else
        self
      end
    end

    scope :for_company_admin, lambda { |user|
      join_clause = if parent_class_type.name == name
                      joins(:entity)
                    else
                      joins(parent_class_type.name.underscore.to_sym)
                    end

      if user.entity_type == "Group Company"
        join_clause.where("#{parent_class_type.name.underscore.pluralize}.entity_id in (?)", user.entity.child_ids)
      else
        join_clause.where("#{parent_class_type.name.underscore.pluralize}.entity_id = ?", user.entity_id)
      end
    }

    scope :for_employee, lambda { |user|
      join_clause = if instance_methods.include?(:access_rights)
                      joins(:access_rights)
                    else
                      joins(parent_class_type.name.underscore => :access_rights)
                    end
      if user.entity_type == "Group Company"
        join_clause.where("#{parent_class_type.name.underscore.pluralize}.entity_id in (?) and access_rights.user_id=?", user.entity.child_ids, user.id)
      else
        join_clause.where("#{parent_class_type.name.underscore.pluralize}.entity_id=? and access_rights.user_id=? and access_rights.entity_id=?", user.entity_id, user.id, user.entity_id)
      end
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

      unless %w[KpiReport Kpi].include?(name)
        # Ensure the investor access is approved
        join_clause = join_clause.joins(entity: :investor_accesses).merge(InvestorAccess.approved_for_user(user))
      end

      join_clause
    }
  end
end
