class KanbanBoard < ApplicationRecord
  include Trackable.new
  include CurrencyHelper

  belongs_to :owner, polymorphic: true, optional: true
  belongs_to :entity
  has_many :kanban_columns, -> { order(:sequence) }, dependent: :destroy
  has_many :kanban_cards, through: :kanban_columns

  after_create :post_create_ops
  after_save_commit :broadcast_board_event, if: -> { saved_change_to_name? }

  OWNER_TYPES = {
    Blank: "blank",
    InvestorKyc: "investor_name",
    Deal: "name"
  }.freeze

  OWNER_TYPES_FORM_NAMES = {
    None: "KanbanBoard",
    Deal: "Deal"
  }.freeze

  def self_owned?
    owner == self
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[kanban_columns kanban_cards]
  end

  def broadcast_board_event
    broadcast_update partial: "/boards/kanban_show"
  end

  def update_cards(card_view_attrs)
    currency_unit = owner.currency == "INR" ? "Crores" : "Million"
    kanban_cards.each do |card|
      info_field = ""
      if card_view_attrs.present?
        card_view_attrs.each do |attr|
          # info_field += "#{attr}: #{send(attr)}\n" if send(attr).present?
          res = card.data_source.send(attr)
          val = res.instance_of?(::Money) ? money_to_currency(res, { units: currency_unit }) : res
          val ||= "-"
          info_field += "#{val},"
        end
      end
      # rubocop:disable Rails/SkipsModelValidations
      card.update_columns(info_field:)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  def post_create_ops
    self.owner = self if owner_id.nil?
    create_columns
  end

  def create_columns
    return unless owner

    step_names = owner.entity.entity_setting.kanban_steps[owner_type] || ["Example Step"]
    kanban_columns = []
    step_names.each_with_index do |step_name, index|
      kanban_columns << { name: step_name.strip, sequence: index + 1, entity_id:, kanban_board_id: id }
    end
    # rubocop:disable Rails/SkipsModelValidations
    KanbanColumn.insert_all(kanban_columns)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def to_s
    name
  end
end
