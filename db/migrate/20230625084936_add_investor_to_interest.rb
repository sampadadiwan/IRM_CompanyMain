class AddInvestorToInterest < ActiveRecord::Migration[7.0]
  def change
    add_reference :interests, :investor, null: true, foreign_key: true
    Interest.all.each do |interest|
      investor = interest.entity.investors.where(investor_entity_id: interest.user.entity_id).first
      interest.update_column(:investor_id, investor&.id)
    end
  end
end
