class ExpandAccessRightCategory < ActiveRecord::Migration[7.2]
  def change
    # AccessRight.where.not(access_to_category: nil).each do |access_right|
    #   dup = access_right.dup
    #   entity = access_right.entity
      
    #   # Remove the orignal access_right
    #   access_right.destroy

    #   # For each investor in the category, add access_right
    #   entity.investors.where(category: access_right.access_to_category).each do |investor|
    #     ar = dup.dup
    #     ar.access_to_category = nil
    #     ar.access_to_investor_id = investor.id
    #     ar.notify = false
    #     ar.save
    #   end
    # end
  end
end
