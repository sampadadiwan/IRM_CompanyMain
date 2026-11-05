# ② H18: a result shows the setup that applied on its day — read from the snapshot stored in the
# result's working (version, classification, override in force), never from today's setup.
module ComplianceSetupAsOf
  module_function

  def call(result)
    w = result.working_hash
    { "version" => w["version"], "classification" => w["classification"],
      "override" => w["override"].presence || "No override", "pending_override" => w["pending_override"],
      "limit" => result.limit_value }
  end
end
