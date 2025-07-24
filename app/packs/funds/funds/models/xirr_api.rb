# This depends on a service for XIRR
# see: https://github.com/thimmaiah/xirr_py

# Deployed as: https://hub.docker.com/repository/docker/thimmaiah/xirr_py/general

# Ensure you run: docker run -p 8000:80 thimmaiah/xirr_py

class XirrApi
  include HTTParty

  debug_output $stdout
  attr_accessor :debug # Rails.env.development?

  def xirr(cash_flows, caller_id = nil)
    response = HTTParty.post(
      "#{ENV.fetch('XIRR_API', nil)}/calculate_xirr?caller_id=#{caller_id}",
      headers: {
        'Content-Type' => 'application/json'
      },
      body: cash_flows.to_json,
      debug_output: @debug ? $stdout : nil
    )
    Rails.logger.debug response
    response["xirr"]
  end

  def check(caller_id: "health_check")
    response = HTTParty.get(
      "#{ENV.fetch('XIRR_API', nil)}/?caller_id=#{caller_id}",
      headers: {
        'Content-Type' => 'application/json'
      },
      body: {},
      debug_output: @debug ? $stdout : nil
    )
    Rails.logger.debug response
    response
  end
end
