class ShareholderPosition < ApplicationRecord
  include Trackable.new

  # The main Group a shareholder position belongs to is a fixed, non-user-editable list.
  # Only `subgroup` is free text that users may set to further split a Group.
  DEFAULT_CATEGORIES = %w[Founder Self Other Employee].freeze
  CATEGORIES = DEFAULT_CATEGORIES.freeze

  # Only a re-uploaded Fully Diluted Quantity/% for an already-approved position is staged for
  # review (see ImportShareholderPosition#save_row) - accepting it can shift this round's %
  # stake totals for every other investor, unlike Quantity Actuals which always applies
  # immediately. "approved" is the default so every pre-existing row and every brand-new
  # (non-conflicting) upload behaves exactly as before this enum was introduced.
  enum :status, { unapproved: 'unapproved', approved: 'approved' }, default: :approved

  belongs_to :entity
  belongs_to :investor
  belongs_to :portfolio_company, class_name: 'Investor', optional: true
  belongs_to :fund, optional: true
  belongs_to :import_upload, optional: true
  belongs_to :approved_by, class_name: 'User', foreign_key: :approved_by_user_id, optional: true

  # `position_date` is the DB column; keep `as_of` as an alias for backwards compatibility
  alias_attribute :as_of, :position_date

  # A position is snapshotted either by a real calendar date (`position_date`, e.g. from an
  # "As Of" column like "March 2025") or by an arbitrary round name (`round_name", e.g. an
  # "As Of" column containing "Secondary Sale" that isn't a recognizable date). Exactly one
  # of the two identifies the snapshot.
  validates :position_type, presence: true
  validates :position_type, length: { maximum: 50 }
  validates :position_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :quantity_actual, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :fully_diluted_percentage, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :subgroup, length: { maximum: 100 }, allow_nil: true
  validates :instrument, length: { maximum: 100 }, allow_nil: true
  validates :round_name, length: { maximum: 255 }, allow_nil: true
  validate :position_date_or_round_name_present

  scope :latest_by_date, -> { order(as_of: :desc) }

  # Finds the already-approved position (if any) that a newly uploaded row for the same
  # investor/round/instrument would update. Used both by the importer (to decide whether a new
  # Fully Diluted Quantity/% must be staged rather than saved directly) and by the approver (to
  # know which approved row to overwrite once a staged update is accepted).
  #
  # Matched on investor identity (investor_label when present - the uploaded ShareHolder name -
  # else the linked Investor record) + round (round_name or position_date, whichever the position
  # uses) + instrument, NOT on category/quantity_actual - those may legitimately be corrected as
  # part of accepting an update and don't identify "the same holding".
  def self.find_matching_approved(portfolio_company_id:, round_name:, position_date:, instrument: nil, investor_label: nil, investor_id: nil, exclude_id: nil)
    scope = approved.where(portfolio_company_id: portfolio_company_id, instrument: instrument)
    scope = exclude_id ? scope.where.not(id: exclude_id) : scope
    scope = if investor_label.present?
              scope.where(investor_label: investor_label)
            else
              scope.where(investor_id: investor_id, investor_label: nil)
            end
    scope = if round_name.present?
              scope.where(round_name: round_name)
            else
              scope.where(round_name: nil, position_date: position_date)
            end
    scope.first
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[category subgroup instrument round_name position_date investor_label status position_amount quantity_actual fully_diluted_percentage]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[investor portfolio_company fund]
  end

  # Whether this Portfolio Company + Round combination has any Fully Dilluted % data at all to
  # check - a round nobody ever typed a % into (quantity-only rows) has nothing to verify, so the
  # combined-total check (round_percentage_total) should never be applied to it.
  def self.round_percentage_check_applicable?(portfolio_company_id:, round_name:, position_date:)
    scope = where(portfolio_company_id: portfolio_company_id).where.not(fully_diluted_percentage: nil)
    scope = round_name.present? ? scope.where(round_name: round_name) : scope.where(round_name: nil, position_date: position_date)
    scope.exists?
  end

  # Whether this pending (unapproved) row is a *pure* Fully Dilluted % change - i.e. its matching
  # already-approved sibling has the exact same Quantity/Quantity Actuals and only the % differs
  # (see ImportShareholderPosition#save_row, which stages both fields it didn't change straight
  # from the existing approved row). Used to force these through the batch "Accept All"/"Reject
  # All" flow (ShareholderPositionPolicy#individually_approvable?) instead of one-off approval:
  # approving a single %-only change out of a round-wide rebalance (e.g. two rows swapping a few
  # points between them) leaves that round's % total inconsistent until every other %-only change
  # uploaded alongside it is approved too. A row that also changes Quantity/Quantity Actuals, or
  # has no matching approved sibling at all (a brand-new position), is unaffected and can still be
  # approved/rejected individually.
  def percentage_only_pending_update?
    return false unless unapproved?

    matching_approved = self.class.find_matching_approved(
      portfolio_company_id: portfolio_company_id,
      investor_label: investor_label,
      investor_id: investor_id,
      instrument: instrument,
      round_name: round_name,
      position_date: position_date
    )
    return false unless matching_approved

    position_amount == matching_approved.position_amount &&
      quantity_actual == matching_approved.quantity_actual &&
      fully_diluted_percentage != matching_approved.fully_diluted_percentage
  end

  # For a Portfolio Company + Round (round_name or position_date), sums the *effective* Fully
  # Dilluted % across every distinct holding (Shareholder/instrument) in that round - the total a
  # cap table snapshot for the round should reach 100%. A holding with both an already-approved
  # position and a newer staged (unapproved) update counts only the staged %, since that's the
  # value that will actually apply once accepted; counting both would double-count the same
  # holding. Holdings with no Fully Dilluted % typed in at all contribute nothing (there's no %
  # to check for them). Used both right after an upload saves new/staged rows (see
  # ImportShareholderPosition#round_percentage_total_errors_for_upload) and again right before a
  # staged update is accepted (see ShareholderPositionApprover), since the round's data can shift
  # between those two points.
  def self.round_percentage_total(portfolio_company_id:, round_name:, position_date:)
    scope = where(portfolio_company_id: portfolio_company_id).where.not(fully_diluted_percentage: nil)
    scope = round_name.present? ? scope.where(round_name: round_name) : scope.where(round_name: nil, position_date: position_date)

    scope.group_by { |position| [position.investor_label.presence || position.investor_id, position.instrument] }
         .sum { |_holding_key, positions| (positions.find(&:unapproved?) || positions.first).fully_diluted_percentage.to_f }
  end

  private

  def position_date_or_round_name_present
    return if position_date.present? || round_name.present?

    errors.add(:base, "Position date or round name must be present")
  end
end
