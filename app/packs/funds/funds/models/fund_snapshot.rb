class FundSnapshot < FundBase
  # This has all the utility methods required for snashots
  include WithSnapshot

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

  def to_s
    "#{name} - Snapshot:#{snapshot_date}"
  end
end
