module AccessRightsHelper
  def initialize_from_params(access_right_params)
    access_rights = []
    # owner = nil

    if access_right_params[:access_to_category].present? || access_right_params[:user_id].present?
      # We get multiple categories to be given access at the same time
      return create_from_category(access_right_params)
    elsif access_right_params[:access_to_investor_id].present?
      # We get multiple investors to be given access at the same time
      return create_from_investor(access_right_params)
    else
      # This is not for access_to_category or access_to_investor_id
      access_right = AccessRight.new(access_right_params)
      access_right.entity_id = current_user.entity_id
      authorize access_right
      access_rights << access_right
      # owner = access_right.owner
    end

    access_rights
  end

  private

  def create_from_investor(access_right_params)
    access_rights = []
    # owner = nil

    if access_right_params[:access_to_investor_id].present?
      # We get multiple investors to be given access at the same time
      # owner = AccessRight.new(access_right_params).owner
      access_right_params[:access_to_investor_id].each do |investor_id|
        # next if investor_id.blank? # Sometimes we get a blank

        access_right = AccessRight.new(access_right_params)
        access_right.access_to_investor_id = investor_id
        access_right.user_id = user_id
        access_right.entity_id = current_user.entity_id
        authorize access_right
        # owner.access_rights << access_right
        access_rights << access_right
      end
    end

    access_rights
  end

  def create_from_category(access_right_params)
    access_rights = []
    # owner = nil

    if access_right_params[:access_to_category].present?
      # We get multiple categories to be given access at the same time
      # owner = AccessRight.new(access_right_params).owner
      access_right_params[:access_to_category].each do |category|
        access_right = AccessRight.new(access_right_params)
        access_right.access_to_category = category
        access_right.entity_id = current_user.entity_id
        authorize access_right
        # owner.access_rights << access_right
        access_rights << access_right
      end
    end

    access_rights
  end
end
