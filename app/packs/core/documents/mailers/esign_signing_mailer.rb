# The email a signer gets when it is their turn to sign inside CapHive (see EsignSigningNotifier).
class EsignSigningMailer < ApplicationMailer
  helper ApplicationHelper

  before_action :set_e_signature
  def set_e_signature
    @e_signature = ESignature.find params[:e_signature_id]
    @document = @e_signature.document
  end

  def signature_requested
    send_mail(subject: "Your signature is requested: #{@document.name}")
  end
end
