class RemoveHoldingEntity < ActiveRecord::Migration[7.2]
  def change
    # EntitySetting.with_deleted.joins(:entity).where("entities.entity_type": ["Holding", "Trust"]).each(&:really_destroy!)
    # Entity.with_deleted.where("entities.entity_type": ["Holding", "Trust"]).each(&:really_destroy!)
  end
end
