module KanbanCardManager
  extend ActiveSupport::Concern
  include CurrencyHelper

  included do
    after_commit :create_or_update_kanban_card, on: %i[create update]
    after_destroy :destroy_kanban_card
    attr_accessor :kanban_column_id
  end

  def get_data
    send(:"#{self.class.name.underscore}_data")
  end

  def kanban_card
    KanbanCard.find_by(data_source_type: self.class.name, data_source_id: id)
  end

  PARENT_MAPPING = {
    "KanbanCard" => "KanbanBoard",
    "DealInvestor" => "Deal"
  }.freeze

  def get_card_attributes
    data_source_parent_class = PARENT_MAPPING[self.class.name]
    data_source_parent = send(data_source_parent_class.downcase)
    kanban_board = KanbanBoard.find_by(owner_type: data_source_parent_class, owner_id: data_source_parent.id)
    return unless kanban_board

    data = get_data
    {
      kanban_board_id: kanban_board.id,
      kanban_column_id: data.kanban_column_id || kanban_board.kanban_columns.first.id,
      data_source_id: id,
      data_source_type: self.class.name,
      entity_id:,
      title: data.title,
      info_field: data.info_field,
      notes: data.notes,
      tags: data.tags
    }
  end

  def create_or_update_kanban_card
    return if deleted?

    kanban_card_attrs = get_card_attributes
    return if kanban_card_attrs.nil?

    kanban_card = KanbanCard.find_by(data_source_type: self.class.name, data_source_id: id)
    if kanban_card
      kanban_card_attrs.delete_if { |_key, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
      kanban_card_attrs = kanban_card.attributes.merge!(kanban_card_attrs)
      kanban_card.assign_attributes(kanban_card_attrs.except(:notes))
      kanban_card.notes = kanban_card_attrs["notes"]
      kanban_card.save!
    else
      KanbanCard.create!(kanban_card_attrs)
    end
  end

  def destroy_kanban_card
    kanban_card = KanbanCard.find_by(data_source_type: self.class.name, data_source_id: id)
    kanban_card.destroy
  end

  def deal_investor_data
    card = kanban_card
    data = kanban_card_struct
    data.title = investor_name
    currency_unit = deal.currency == "INR" ? "Crores" : "Million"
    data.info_field = money_to_currency(total_amount, { units: currency_unit })
    data.notes = notes
    data.tags = tags
    data.kanban_column_id = kanban_column_id.presence || card&.kanban_column_id
    data.info_field = ""
    if deal.card_view_attrs.present?
      deal.card_view_attrs.each do |attr|
        # data.info_field += "#{attr}: #{send(attr)}\n" if send(attr).present?
        res = send(attr)
        val = res.instance_of?(::Money) ? money_to_currency(res, { units: currency_unit }) : res
        val ||= "-"
        data.info_field += "#{val}," if val.present?
      end
    else
      data.info_field = money_to_currency(total_amount, { units: currency_unit })
    end
    data
  end

  def kanban_card_struct
    data = OpenStruct.new
    data.title = nil
    data.info_field = nil
    data.tags = nil
    data.notes = nil
    data.kanban_column_id = nil
    data
  end
end
