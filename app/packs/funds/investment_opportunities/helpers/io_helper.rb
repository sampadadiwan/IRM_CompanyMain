module IoHelper
  def io_magic_link(io, current_user)
    signed_id = io.signed_id(expires_in: 7.days, purpose: "shared_by_#{current_user.id}")
    subdomain = io.entity.sub_domain
    no_password_show_investment_opportunities_url(signed_id:, subdomain:, preview: true, shared_by: current_user.id)
  end
end
