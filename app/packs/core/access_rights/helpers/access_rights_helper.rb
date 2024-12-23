module AccessRightsHelper
  def initialize_from_params(access_right_params)
    access_rights = []
    # owner = nil

    if access_right_params[:access_to_category].present?
      # We get multiple categories to be given access at the same time
      return create_from_category(access_right_params)
    elsif access_right_params[:tag_list].present?
      # We get multiple categories to be given access at the same time
      return create_from_tag_list(access_right_params)
    elsif access_right_params[:access_to_investor_id].present?
      # We get multiple investors to be given access at the same time
      return create_from_investor(access_right_params)
    elsif access_right_params[:user_id].present?
      # We get multiple investors to be given access at the same time
      return create_from_user(access_right_params)
    else
      Rails.logger.debug { "AccessRightsHelper:  default called with #{access_right_params}" }
      # This is not for access_to_category or access_to_investor_id
      access_right = AccessRight.new(access_right_params)
      access_right.entity_id = access_right.owner&.entity_id || current_user.entity_id
      authorize access_right
      access_rights << access_right
      # owner = access_right.owner
    end

    access_rights
  end

  private

  def create_from_investor(access_right_params)
    Rails.logger.debug { "AccessRightsHelper:  create_from_investor called with #{access_right_params}" }
    access_rights = []
    # owner = nil

    if access_right_params[:access_to_investor_id].present?
      # We get multiple investors to be given access at the same time
      # owner = AccessRight.new(access_right_params).owner
      access_right_params[:access_to_investor_id].each do |investor_id|
        # next if investor_id.blank? # Sometimes we get a blank

        access_right = AccessRight.new(access_right_params)
        access_right.access_to_investor_id = investor_id
        access_right.entity_id = access_right.owner&.entity_id || current_user.entity_id
        authorize access_right
        # owner.access_rights << access_right
        access_rights << access_right
      end
    end

    access_rights
  end

  def create_from_user(access_right_params)
    Rails.logger.debug { "AccessRightsHelper:  create_from_user called with #{access_right_params}" }
    access_rights = []
    # owner = nil

    if access_right_params[:user_id].present?
      # We get multiple investors to be given access at the same time
      # owner = AccessRight.new(access_right_params).owner
      access_right_params[:user_id].each do |user_id|
        # next if investor_id.blank? # Sometimes we get a blank

        access_right = AccessRight.new(access_right_params)
        access_right.user_id = user_id
        access_right.entity_id = access_right.owner&.entity_id || current_user.entity_id
        authorize access_right
        # owner.access_rights << access_right
        access_rights << access_right
      end
    end

    access_rights
  end

  def create_from_category(access_right_params)
    Rails.logger.debug { "AccessRightsHelper:  create_from_category called with #{access_right_params}" }
    access_rights = []
    # owner = nil

    if access_right_params[:access_to_category].present?
      # We get multiple categories to be given access at the same time
      access_right_params[:access_to_category].each do |category|
        # Get the investors with this category for the entity
        current_user.entity.investors.where(category: category.strip).find_each do |investor|
          # For each investor, create an access right
          access_right = AccessRight.new(access_right_params)
          # We will remove the category and add the investor_id
          access_right.access_to_category = nil
          access_right.access_to_investor_id = investor.id
          access_right.entity_id = access_right.owner&.entity_id || current_user.entity_id
          authorize access_right
          # owner.access_rights << access_right
          access_rights << access_right
        end
      end
    end

    access_rights
  end

  def create_from_tag_list(access_right_params)
    Rails.logger.debug { "AccessRightsHelper:  create_from_tag_list called with #{access_right_params}" }
    access_rights = []
    # owner = nil

    if access_right_params[:tag_list].present?
      # We get multiple categories to be given access at the same time
      access_right_params[:tag_list].split(",").each do |tag|
        # Get the investors with this category for the entity
        current_user.entity.investors.where("tag_list like :tag", { tag: "%#{tag.strip}%" }).find_each do |investor|
          # For each investor, create an access right
          access_right = AccessRight.new(access_right_params)
          # We will remove the category and add the investor_id
          access_right.access_to_category = nil
          access_right.access_to_investor_id = investor.id
          access_right.entity_id = access_right.owner&.entity_id || current_user.entity_id
          authorize access_right
          # owner.access_rights << access_right
          access_rights << access_right
        end
      end
    end

    access_rights
  end
end
