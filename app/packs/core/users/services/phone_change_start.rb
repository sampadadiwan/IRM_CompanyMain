# Starts a change of a user's EXISTING mobile number: checks the new number, opens a
# PhoneChangeRequest and emails a 6-digit code to the user. Nothing on the user changes
# until PhoneChangeConfirm accepts that code.
#
# The code always goes to the TARGET user's email — which cannot change
# (User#email_cannot_change) — so an administrator changing someone else's number needs that
# person to read the code out, and a hijacked session cannot complete it without the mailbox.
#
# Authorization is the controller's job (UserPolicy#change_phone?).
#
# Usage:
#   result = PhoneChangeStart.call(user: target, actor: current_user, call_code: "91", phone: "9876543210")
#   result.success? / result[:errors]
class PhoneChangeStart < Trailblazer::Operation
  step :ensure_existing_phone
  step :validate_new_number
  step :enforce_rate_limit
  # Single failure handler: a failing step above jumps to the left track and lands here.
  left :handle_errors, Output(:failure) => End(:failure)
  step :open_request
  step :email_code

  # A user without a number adds one from the edit form, no code needed.
  def ensure_existing_phone(ctx, user:, **)
    return true if user.phone.present?

    ctx[:errors] = "This user has no mobile number yet — add one from Edit, no code is needed."
    false
  end

  # Same checks the edit form applies (normalisation, presence, dialable), plus "actually
  # different", run on a throwaway copy so the real user object is never dirtied.
  def validate_new_number(ctx, user:, **)
    probe = User.new(call_code: ctx[:call_code].to_s.strip, phone: ctx[:phone].to_s)
    ctx[:new_call_code] = probe.call_code
    ctx[:new_phone] = probe.phone

    if ctx[:new_phone].blank? || ctx[:new_call_code].blank?
      ctx[:errors] = "Enter both the country code and the new mobile number."
    elsif ctx[:new_phone] == user.phone && ctx[:new_call_code] == user.call_code.to_s.strip
      ctx[:errors] = "That is already this user's mobile number."
    else
      # User's own phone validations (length, phone_must_be_dialable) — the same rule and
      # message the edit form gives. The probe is a new record, so the change-only guard on
      # phone_must_be_dialable is satisfied and it always runs.
      probe.validate
      phone_error = probe.errors.full_messages_for(:phone).first
      ctx[:errors] = "#{phone_error}." if phone_error
    end
    ctx[:errors].nil?
  end

  # Each request sends an email; cap how often, per target user.
  def enforce_rate_limit(ctx, user:, **)
    recent = user.phone_change_requests.since(1.hour.ago)
    if recent.since(PhoneChangeRequest::RESEND_COOLDOWN.ago).exists?
      ctx[:errors] = "A code was sent less than a minute ago. Please wait a moment before asking for another."
    elsif recent.count >= PhoneChangeRequest::HOURLY_LIMIT
      ctx[:errors] = "Too many phone change requests in the last hour. Please try again later."
    end
    ctx[:errors].nil?
  end

  def handle_errors(ctx, user:, **)
    Rails.logger.warn "[PhoneChangeStart] user_id=#{user.id} refused: #{ctx[:errors]}"
    false
  end

  # Supersedes any earlier pending request (its code stops working) and opens a new one.
  # The new request has no code yet — SendPhoneChangeCodeJob generates and emails it.
  def open_request(ctx, user:, actor:, **)
    now = Time.current

    ActiveRecord::Base.connected_to(role: :writing) do
      PhoneChangeRequest.transaction do
        # At most a handful of rows per user (HOURLY_LIMIT), so a per-row update is fine.
        user.phone_change_requests.pending.find_each { |r| r.update!(cancelled_at: now) }

        ctx[:request] = user.phone_change_requests.create!(requested_by: actor, new_call_code: ctx[:new_call_code],
                                                           new_phone: ctx[:new_phone], expires_at: now + PhoneChangeRequest::CODE_TTL)
      end
    end
    true
  end

  # Only the request id goes on the queue; the job makes the code (see SendPhoneChangeCodeJob).
  # Enqueued after the transaction above has committed, so the job always finds the row.
  def email_code(_ctx, request:, **)
    SendPhoneChangeCodeJob.perform_later(request.id)
    true
  end
end
