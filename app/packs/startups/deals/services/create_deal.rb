class CreateDeal < DealActions
  step :active_deal, Output(:failure) => End(:failure)
  step :create_activity_template
  step :sync_kanban_columns
  step :create_deal_documents_folder
  left :handle_errors, Output(:failure) => End(:failure)

  def active_deal(ctx, deal:, current_user: nil, **)
    ApplicationRecord.transaction do
      unless deal.save
        Rails.logger.error deal.errors.full_messages
        ctx[:errors] = deal.errors.full_messages.join(", ")
        raise ActiveRecord::Rollback
      end

      unless grant_creator_access_right(deal, current_user)
        ctx[:errors] = "Could not grant full access to deal creator"
        raise ActiveRecord::Rollback
      end

      create_activity_template_records(ctx, deal)

      deal.entity.active_deal_id = deal.id
      deal.entity.save
    end

    ctx[:errors].blank?
  end

  def create_activity_template(_ctx, deal:, **)
    true
  end

  private

  def grant_creator_access_right(deal, current_user)
    return true if current_user.blank?
    return true unless current_user.curr_role == "employee"
    return true if current_user.has_cached_role?(:company_admin)

    access_right = AccessRight.find_or_initialize_by(
      owner: deal,
      entity_id: deal.entity_id,
      user_id: current_user.id
    )

    # Preserve explicit admin-managed overrides when an access right already exists.
    return true unless access_right.new_record?

    access_right.access_type = "Deal"
    access_right.granted_by = current_user
    access_right.notify = false
    access_right.permissions = 0
    %i[create read update destroy].each { |perm| access_right.permissions.set(perm) }
    access_right.save
  end

  def create_activity_template_records(ctx, deal)
    # Skip entirely when the user checked "No Templates" at creation time.
    return if deal.skip_templates.present?

    # D2: a new deal's steps are numbered 1, 2, 3... with no steps there yet, so each is an append and
    # acts_as_list has no later step to shift - skip its shift UPDATE per step. A deal that already has template
    # steps takes the normal path.
    if DealActivity.templates(deal).none?
      DealActivity.acts_as_list_no_update { create_template_steps(deal) }
    else
      create_template_steps(deal)
    end
  rescue StandardError => e
    Rails.logger.error e.message
    Rails.logger.error e.backtrace
    ctx[:errors] = e.message
    raise ActiveRecord::Rollback
  end

  # The deal's template steps, numbered from 1: copied from the deal it is cloned from, or the configured defaults
  def create_template_steps(deal)
    seq = 1
    if deal.clone_from_id.present?
      clone_from = Deal.find(deal.clone_from_id)
      DealActivity.templates(clone_from).each do |template|
        DealActivity.create!(deal_id: deal.id, deal_investor_id: nil, status: "Template",
                             entity_id: deal.entity_id, title: template.title, sequence: seq, days: template.days)
        seq += 1
      end
    else
      template_configs = deal.entity.is_fund? ? Deal::FUND_ACTIVITIES : Deal::ACTIVITIES
      template_configs.each do |title, days|
        DealActivity.create!(deal_id: deal.id, deal_investor_id: nil, status: "Template",
                             entity_id: deal.entity_id, title:, sequence: seq, days: days.to_i)
        seq += 1
      end
    end
  end

  def sync_kanban_columns(_ctx, deal:, **)
    deal.kanban_board&.sync_columns_from_deal_activities
    true
  end
end
