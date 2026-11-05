# ① Rule Library (super admins) and entity packs (editors). CapHive draft packs stay private (H1).
class CompliancePacksController < ApplicationController
  before_action :set_pack, only: %i[show retire]

  def index
    authorize CompliancePack
    @packs = policy_scope(CompliancePack).includes(:versions).order(:name)
  end

  def show
    authorize @pack
    @versions = @pack.versions.sort_by(&:version_no)
  end

  def new
    @pack = CompliancePack.new
    authorize @pack, :create?
  end

  # Entity packs belong to the user's firm; only super admins create CapHive packs (entity_id nil)
  def create
    @pack = CompliancePack.new(pack_params)
    @pack.entity_id = current_user.has_cached_role?(:super) && params[:caphive] == "1" ? nil : current_user.entity_id
    @pack.locked = @pack.caphive?
    authorize @pack, :create?
    if @pack.save
      @pack.versions.create!(version_no: 1, definition: { "classifications" => default_classifications })
      redirect_to compliance_pack_path(@pack), notice: "Pack created"
    else
      render :new, status: :unprocessable_content
    end
  end

  def retire
    authorize @pack
    @pack.update!(retired_on: params[:retired_on].presence || Time.zone.today)
    redirect_to compliance_pack_path(@pack), notice: "Pack retired"
  end

  private

  def set_pack
    @pack = policy_scope(CompliancePack).find_by(id: params[:id]) || raise(Pundit::NotAuthorizedError)
  end

  def pack_params
    params.expect(compliance_pack: %i[name regime time_zone])
  end

  def default_classifications
    ["All funds"]
  end
end
