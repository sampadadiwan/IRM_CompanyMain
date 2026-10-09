# Test-only workflow checks, so engine scenarios can drive system steps without a capital call.
#
# test.flag_1 / test.flag_2 / test.flag_3 pass when the workflowable's json_fields["flag_N"] is
# "yes"; test.skip is used as a skip key and is true when json_fields["skip"] is "yes". They apply
# to any workflowable type (workflowable_type nil).
class WorkflowTestFlagCheck < WorkflowChecks::Base
  def call(record)
    # The flag name is the part of the key after "test."
    flag = self.class.key.delete_prefix("test.")
    value = record.json_fields.to_h[flag].to_s

    if value == "yes"
      pass(message: "#{flag} is set", passed_since: record.updated_at)
    else
      fail_with(message: "Waiting for #{flag}")
    end
  end
end

# One registered subclass per key; registered after boot, so after the initializer's reset!
%w[flag_1 flag_2 flag_3 skip].each do |flag|
  klass = Class.new(WorkflowTestFlagCheck) do
    self.key = "test.#{flag}"
    self.label = "Test #{flag.humanize.downcase}"
  end
  WorkflowChecks::Registry.register(klass)
end

# A check tied to a different record type, to prove a Capital Call template can't use it
class WorkflowTestKycFlagCheck < WorkflowTestFlagCheck
  self.key = "test_kyc.flag"
  self.label = "Test kyc flag"
  self.workflowable_type = "InvestorKyc"
end
WorkflowChecks::Registry.register(WorkflowTestKycFlagCheck)

# A check that always raises, to prove the evaluator reports it and stops the walk (X6)
class WorkflowTestRaisingCheck < WorkflowChecks::Base
  self.key = "test.raises"
  self.label = "Test raises"

  def call(_record)
    raise "test check failure"
  end
end
WorkflowChecks::Registry.register(WorkflowTestRaisingCheck)

# Always passes: used on acknowledge steps, whose real gate is the person's confirmation
class WorkflowTestAlwaysCheck < WorkflowChecks::Base
  self.key = "test.always"
  self.label = "Test always"

  def call(_record)
    pass(message: "Ready for review")
  end
end
WorkflowChecks::Registry.register(WorkflowTestAlwaysCheck)
