# Finishes a change of a user's existing mobile number: checks the code the user received by
# email against the latest pending PhoneChangeRequest and, if it matches, saves the new number
# through User#apply_verified_phone_change! — the only in-app path past
# User#existing_phone_change_must_be_verified.
#
# Authorization is the controller's job (UserPolicy#change_phone?).
#
# Usage:
#   result = PhoneChangeConfirm.call(user: target, actor: current_user, code: params[:code])
#   result.success? / result[:errors] / result[:request_open]
class PhoneChangeConfirm < Trailblazer::Operation
  step :find_request
  step :check_code
  # Single failure handler: a failing step above jumps to the left track and lands here.
  left :handle_errors, Output(:failure) => End(:failure)
  step :apply_change
  step :notify_user

  # The newest request still waiting for a code. Expired ones are reported as expired, not
  # as missing, so the user knows to ask for a new code.
  def find_request(ctx, user:, **)
    request = user.phone_change_requests.pending.order(created_at: :desc).first
    if request.nil?
      ctx[:errors] = "There is no phone change waiting for a code. Start again from the user page."
    elsif request.expired?
      ctx[:errors] = "That code has expired. Start the phone change again to get a new one."
    else
      ctx[:request] = request
    end
    ctx[:errors].nil?
  end

  # Counts the attempt BEFORE comparing, so a guess is spent even if the compare raises.
  # The last wrong guess cancels the request; a right code after that is refused.
  def check_code(ctx, request:, **)
    ActiveRecord::Base.connected_to(role: :writing) do
      request.increment!(:attempts)
      return true if request.code_matches?(ctx[:code])

      if request.attempts_left.zero?
        request.update!(cancelled_at: Time.current)
        ctx[:errors] = "Too many wrong codes. Start the phone change again to get a new code."
      else
        # The page can show the code box again while the request is still open.
        ctx[:request_open] = true
        ctx[:errors] = "That code is not correct. #{request.attempts_left} #{'attempt'.pluralize(request.attempts_left)} left."
      end
    end
    false
  end

  def handle_errors(ctx, user:, **)
    Rails.logger.warn "[PhoneChangeConfirm] user_id=#{user.id} refused: #{ctx[:errors]}"
    false
  end

  # Saves the number and closes the request together. `audit_comment` rides on the audited
  # user row so the audit log says who changed it and that it was code-confirmed.
  def apply_change(ctx, user:, actor:, request:, **)
    ctx[:previous_masked_phone] = user.masked_phone_with_call_code
    who = user.id == actor.id ? "self" : "user ##{actor.id}"

    ActiveRecord::Base.connected_to(role: :writing) do
      User.transaction do
        user.apply_verified_phone_change!(call_code: request.new_call_code, phone: request.new_phone,
                                          audit_comment: "Mobile number changed by #{who}, confirmed by emailed code")
        request.update!(verified_at: Time.current)
      end
    end
    Rails.logger.info "[PhoneChangeConfirm] user_id=#{user.id} actor_id=#{actor.id} request_id=#{request.id}"
    true
  end

  # Tells the owner the number changed. If they never asked for it, this email is how they
  # find out. No secret in it, so deliver_later is fine.
  def notify_user(ctx, user:, actor:, **)
    UserMailer.with(entity_id: user.entity_id, user_id: user.id, actor_id: actor.id,
                    previous_masked_phone: ctx[:previous_masked_phone]).phone_changed.deliver_later
    true
  end
end
