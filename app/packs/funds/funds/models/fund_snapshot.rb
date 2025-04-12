class FundSnapshot < FundBase
  self.primary_key = %i[id snapshot_date]

  belongs_to :entity
  # If this is a feeder fund, it will have a ref to the master_fund
  belongs_to :master_fund,
             lambda { |this_fund_snapshot|
               where(snapshot_date: this_fund_snapshot.snapshot_date)
             },
             class_name: "FundSnapshot",
             foreign_key: :master_fund_id,
             primary_key: :id,
             optional: true

  # If this is a master fund, it may have many feeder funds
  has_many :feeder_funds,
           lambda { |this_fund_snapshot|
             where(snapshot_date: this_fund_snapshot.snapshot_date)
           },
           class_name: "FundSnapshot",
           foreign_key: :master_fund_id,
           primary_key: :id

  before_create :set_default_snapshot_date

  # setup the snapshot_date to be the current date
  def set_default_snapshot_date
    self.snapshot_date ||= Time.zone.today
  end

  # Ensure the snapshot can never be modified
  def readonly?
    false # self.snapshot_date.present?
  end

  def self.snapshot(fund)
    attributes = fund.attributes
    # The primary_key is a composite key, so we need to set the snapshot_date
    attributes["id"] = [fund.id, Time.zone.today]
    FundSnapshot.create(attributes)
  end
end
