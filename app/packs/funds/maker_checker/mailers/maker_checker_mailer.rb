# frozen_string_literal: true

# ⑦ Maker–checker emails (OWASP review 2026-11 M13, design card ⑦ "Notifications"): approval requested, approval
# withdrawn, maker–checker turned off. One recipient per notification (MakerCheckerNotifier). Each email says what
# happened, why this person got it and what to do (task U.1). Dates render "Mon dd, yyyy" through
# EmailDateLocalization (bare l(...) in the views, CLAUDE.md). Investors never receive these.
class MakerCheckerMailer < ApplicationMailer
  helper CurrencyHelper
  helper ApplicationHelper
  helper EmailStyleHelper

  # The two records maker–checker covers; the type comes from our own notifier, never from a request, and is mapped
  # here rather than constantized
  APPROVABLES = { "CapitalCall" => CapitalCall, "CapitalDistribution" => CapitalDistribution }.freeze

  def notice
    @kind = params[:kind].to_s
    @message = params[:message].to_s
    @actor = User.with_deleted.find_by(id: params[:actor_id]) if params[:actor_id].present?
    # The call / distribution, scoped to the email's firm (ids only travel in the notification)
    model = APPROVABLES[params[:approvable_type].to_s]
    @record = model&.where(entity_id: @entity.id)&.find_by(id: params[:approvable_id])
    send_mail(subject:)
  end

  private

  # H18 / H22 / H25 — the subject is the headline: what happened, to which record
  def subject
    case @kind
    when "approval_withdrawn" then "Approval of #{@record || 'a record'} was withdrawn"
    when "maker_checker_off" then "Maker–checker for calls and distributions was turned off"
    else @message.truncate(150)
    end
  end
end
