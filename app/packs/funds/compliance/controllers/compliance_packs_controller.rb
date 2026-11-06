# ① Rule Library (super admins) and entity packs (editors). CapHive draft packs stay private (H1).
class CompliancePacksController < ApplicationController
  include ComplianceCrumbs

  before_action :set_pack, only: %i[show retire]

  def index
    authorize CompliancePack
    @q = CompliancePack.ransack(params[:q])
    scope = policy_scope(@q.result).includes(:versions)
    if (value = params.dig(:search, :value)).present?
      scope = scope.where("compliance_packs.name LIKE :like OR compliance_packs.regime LIKE :like",
                          like: "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s.strip)}%")
    end
    @stats_scope = CompliancePack.where(id: scope.select(:id))
    scope = scope.order(:name) if params.dig(:q, :s).blank?
    @pagy, @packs = pagy(scope, limit: params[:per_page] || 10)
    compliance_crumbs(["Rule library", nil])
    # The Compliance hub's lazy Packs pane (R170): this page's content inside the hub frame
    return render_hub_pane(:packs, "compliance_packs/index") if hub_frame_request?(:packs)

    respond_to do |format|
      format.html
      format.turbo_stream { render partial: "compliance_packs/index", locals: { packs: @packs } }
    end
  end

  def show
    authorize @pack
    @versions = @pack.versions.sort_by(&:version_no)
    compliance_crumbs(["Rule library", compliance_packs_path], [@pack.name, nil])
  end

  def new
    @pack = CompliancePack.new
    authorize @pack, :create?
    compliance_crumbs(["Rule library", compliance_packs_path], ["New entity pack", nil])
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
      compliance_crumbs(["Rule library", compliance_packs_path], ["New entity pack", nil])
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
