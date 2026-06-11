class CreateDeal < DealActions
  step :active_deal, Output(:failure) => End(:failure)
  step :create_activity_template
  step :sync_kanban_columns
  step :create_deal_documents_folder
  left :handle_errors, Output(:failure) => End(:failure)

  def active_deal(ctx, deal:, **)
    ApplicationRecord.transaction do
      unless deal.save
        Rails.logger.error deal.errors.full_messages
        ctx[:errors] = deal.errors.full_messages.join(", ")
        raise ActiveRecord::Rollback
      end

      create_activity_template_records(ctx, deal)

      deal.entity.active_deal_id = deal.id
      deal.entity.save
    end

    ctx[:errors].blank?
  end

  def create_activity_template(ctx, deal:, **)
    true
  end

  private

  def create_activity_template_records(ctx, deal)
    # Skip entirely when the user checked "No Templates" at creation time.
    return if deal.skip_templates.present?

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
  rescue StandardError => e
    Rails.logger.error e.message
    Rails.logger.error e.backtrace
    ctx[:errors] = e.message
    raise ActiveRecord::Rollback
  end

  def sync_kanban_columns(_ctx, deal:, **)
    deal.kanban_board&.sync_columns_from_deal_activities
    true
  end
end
