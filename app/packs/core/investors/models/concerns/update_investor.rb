module UpdateInvestor
  extend ActiveSupport::Concern

  included do
    after_commit :update_association_name, only: :update?

    # Be very careful using this method, it is used to move all investors associations to a new investor
    def self.merge(old_investor, new_investor, allow_cross_entity: false)
      raise "Cannot merge investors from different entities" if !allow_cross_entity && old_investor.entity_id != new_investor.entity_id

      # Fund related stuff
      old_investor.investor_kycs.update_all(investor_name: new_investor.investor_name, investor_id: new_investor.id)
      old_investor.capital_commitments.update_all(investor_name: new_investor.investor_name, investor_id: new_investor.id)
      old_investor.expression_of_interests.update_all(investor_id: new_investor.id)

      old_investor.capital_distribution_payments.update_all(investor_name: new_investor.investor_name, investor_id: new_investor.id)
      old_investor.capital_remittances.update_all(investor_name: new_investor.investor_name, investor_id: new_investor.id)
      old_investor.aggregate_portfolio_investments.update_all(portfolio_company_name: new_investor.investor_name, portfolio_company_id: new_investor.id)
      old_investor.portfolio_investments.update_all(portfolio_company_name: new_investor.investor_name, portfolio_company_id: new_investor.id)

      old_investor.fund_units.update_all(investor_id: new_investor.id)
      old_investor.aml_reports.update_all(investor_id: new_investor.id)
      old_investor.approval_responses.update_all(investor_id: new_investor.id)

      # Startup
      old_investor.investments.update_all(investor_id: new_investor.id)
      old_investor.offers.update_all(investor_id: new_investor.id)

      # Other stuff
      old_investor.messages.update_all(investor_id: new_investor.id)
      old_investor.notes.update_all(investor_id: new_investor.id)
      old_investor.deal_investors.update_all(investor_name: new_investor.investor_name, investor_id: new_investor.id, investor_entity_id: new_investor.investor_entity_id)

      # Folder names need to be updates
      new_investor.update_folder_names

      # Also move the access, rights and users
      old_investor.investor_accesses.update_all(investor_id: new_investor.id, investor_entity_id: new_investor.investor_entity_id)

      # We need to be careful about access rights, cannot blindly update
      old_investor.access_rights.each do |old_ar|
        if old_ar.owner.access_rights.where(access_to_investor_id: new_investor.id).any?
          # The new investor already has access, so we can delete the old one
          old_ar.destroy
        else
          # The new investor does not have access, so we can update the old one
          old_ar.update_column(:access_to_investor_id, new_investor.id)
        end
      end

      old_investor.investor_entity.employees.update_all(entity_id: new_investor.investor_entity_id)
      old_investor.update_column(:investor_name, "#{old_investor.investor_name} - Defunct/Inactive")
    end
  end

  # Some associations cache the investor_name, so update that if the name changes here.

  def update_association_name
    # If the investor name changes, we need to update all the associations
    if saved_change_to_investor_name?
      investor_kycs.update_all(investor_name:)
      capital_commitments.update_all(investor_name:)
      capital_distribution_payments.update_all(investor_name:)
      capital_remittances.update_all(investor_name:)
      aggregate_portfolio_investments.update_all(portfolio_company_name: investor_name)
      portfolio_investments.update_all(portfolio_company_name: investor_name)
      deal_investors.update_all(investor_name:)
      update_folder_names

      # Check if investor entity has only one investor, and we changed its name
      if sole_investor?
        # If so also update the entity name
        investor_entity.update(name: investor_name)
      end
    end

    # If the primary email changes, we need to update the investor_entity as well
    investor_entity.update_column(:primary_email, primary_email) if saved_change_to_primary_email? && (sole_investor? || investor_entity.primary_email.blank?)
  end

  # Some folder names have the investor name in it, so if that changes, we need to change folder names
  def update_folder_names
    capital_commitments.each do |cc|
      next unless cc.document_folder

      cc.document_folder.name = cc.folder_path.split("/")[-1]
      cc.document_folder.set_defaults
      cc.document_folder.save
    end
    capital_remittances.each do |cc|
      next unless cc.document_folder

      cc.document_folder.name = cc.folder_path.split("/")[-1]
      cc.document_folder.set_defaults
      cc.document_folder.save
    end
    capital_distribution_payments.each do |cc|
      next unless cc.document_folder

      cc.document_folder.name = cc.folder_path.split("/")[-1]
      cc.document_folder.set_defaults
      cc.document_folder.save
    end
    investor_kycs.each do |kyc|
      next unless kyc.document_folder

      kyc.document_folder.name = kyc.folder_path.split("/")[-1]
      kyc.document_folder.set_defaults
      kyc.document_folder.save
    end
  end

  private

  def sole_investor?
    exclude_category = %w[Trust Founder Employee].include?(category)
    Investor.where(investor_entity_id:).count == 1 && !exclude_category
  end

  def change_investor_entity
    ActiveRecord::Base.transaction do
      # update_column(:investor_entity_id, investor_entity.id)
      old_entity_id = saved_change_to_investor_entity_id&.first
      return unless old_entity_id

      Rails.logger.debug { "Updating investor entity from #{old_entity_id} to #{investor_entity_id}" }
      entity.investor_accesses.where(investor_entity_id: old_entity_id).update_all(investor_entity_id: investor_entity_id)
      entity.deal_investors.where(investor_entity_id: old_entity_id).update_all(investor_entity_id: investor_entity_id)
      InvestorNoticeEntry.where(entity_id:, investor_entity_id: old_entity_id).update_all(investor_entity_id: investor_entity_id)
    end
  rescue StandardError => e
    Rails.logger.error "Error updating investor entity: #{e.message}"
    errors.add(:investor_entity_id, "Could not be updated - #{e.message}")
  end
end
