class RemoveHoldingRole < ActiveRecord::Migration[7.1]
  def change
    User.joins(:entity, :roles).where("entities.entity_type <> 'holding' AND roles.name = 'holding'").each do |user|
      user.remove_role :holding
    end
  end
end
