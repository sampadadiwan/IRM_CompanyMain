class PopulateEntityForInvestmentCriteriaTemplates < ActiveRecord::Migration[8.1]
  def up
    InvestmentCriteriaTemplate.find_each do |template|
      user = User.find_by(id: template.created_by_user_id)
      if user&.entity_id
        template.update_column(:entity_id, user.entity_id)
      else
        # Remove orphaned templates without valid user/entity
        template.destroy
      end
    end
  end

  def down
    InvestmentCriteriaTemplate.update_all(entity_id: nil)
  end
end
