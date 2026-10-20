# frozen_string_literal: true

# The support machine as EC2 sees it, for features/support_console/machine.feature (card ⑨).
#
# Every @support_console scenario starts with no machine found, so the console behaves as it did
# before machine control (a relay that cannot be reached is simply unavailable). A scenario that
# needs a machine sets its state; start and stop move it the way EC2 does, one step per look.
module SupportConsoleMachineStub
  module_function

  def reset!(state: nil, launched: 2.hours.ago, ip: "support-relay.test")
    @state = state
    @launched = launched
    @ip = ip
    @calls = []
    @lookups = []
    Aws.config[:ec2] = { stub_responses: {
      describe_instances: ->(context) { describe(context) },
      start_instances: ->(_context) { record(:start, "pending") },
      stop_instances: ->(_context) { record(:stop, "stopping") }
    } }
  end

  def calls = @calls
  def state = @state
  # The Name tag each lookup asked for (H12, E38, E39)
  def lookups = @lookups

  # pending and stopping settle on the next look, as a real start or stop does
  def describe(context)
    name = context.params[:filters]&.find { |f| f[:name] == "tag:Name" }&.dig(:values, 0)
    @lookups << name
    return { reservations: [] } if @state.nil?

    current = @state
    @state = { "pending" => "running", "stopping" => "stopped" }.fetch(@state, @state)
    { reservations: [{ instances: [{ instance_id: "i-support", private_ip_address: @ip,
                                     launch_time: @launched, state: { name: current } }] }] }
  end

  def record(call, next_state)
    @calls << call
    @state = next_state
    @launched = Time.current if call == :start
    {}
  end
end

Before("@support_console") do
  SupportConsoleMachineStub.reset!
end

After("@support_console") do
  Aws.config.delete(:ec2)
end
