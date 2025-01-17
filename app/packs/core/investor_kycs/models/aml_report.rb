class AmlReport < ApplicationRecord
  belongs_to :investor_kyc
  belongs_to :entity
  belongs_to :investor

  include WithFolder

  enum :match_status, { potential_match: "Potential Match", no_match: "No Match" }

  def generate
    AmlApiResponseService.new.get_response(self)
  end

  def folder_path
    "#{investor_kyc.folder_path}/AML Reports"
  end
end
