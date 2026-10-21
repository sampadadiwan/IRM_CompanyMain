# Emails the code that confirms a change to a user's existing mobile number
# (PhoneChangeStart opens the PhoneChangeRequest, this sends its code).
#
# No code crosses the queue — same rule as SendOtpToSmsJob. Only the request id is a job
# argument; the code is generated here, its digest saved on the request, and the plain code
# exists only in this process and in the email. Passing the code as an argument would
# persist a live credential in Redis and the Sidekiq web UI (and the retry / dead sets on
# failure) for the life of the job record.
#
# A retry generates a NEW code and overwrites the digest, so only the code in the email
# that actually went out can ever match.
class SendPhoneChangeCodeJob < ApplicationJob
  # The user is waiting at the code box, so this is latency-critical like an OTP.
  # :critical is first in the server's queue list (config/initializers/sidekiq.rb).
  queue_as :critical

  # @param request_id [Integer] the PhoneChangeRequest to send a code for
  def perform(request_id)
    request = PhoneChangeRequest.find(request_id)

    # Superseded, confirmed, cancelled or expired while queued: nothing to send, and a
    # retry would not change that.
    if request.verified_at || request.cancelled_at || request.expired?
      Rails.logger.warn "[SendPhoneChangeCodeJob] Skipping request_id=#{request_id}: no longer pending"
      return
    end

    # Generate the code and keep only its digest.
    code = PhoneChangeRequest.generate_code
    ActiveRecord::Base.connected_to(role: :writing) do
      request.code = code
      request.save!
    end

    # deliver_now inside the job: deliver_later would queue the plain code all over again.
    user = request.user
    UserMailer.with(entity_id: user.entity_id, user_id: user.id, actor_id: request.requested_by_id,
                    code:, request_id: request.id).phone_change_code.deliver_now
  end
end
