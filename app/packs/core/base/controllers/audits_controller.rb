class AuditsController < ApplicationController
    after_action :verify_policy_scoped, except: :index
  
    def index
      user_ids = current_user.entity.employees.pluck(:id)
      @audits = Audited::Audit.where(user_id: user_ids).includes(:user)
      @audits = @audits.where(auditable_type: params[:auditable_type]) if params[:auditable_type].present?
      @audits = @audits.where(auditable_id: params[:auditable_id]) if params[:auditable_id].present?
      @audits = @audits.where(user_id: params[:user_id]) if params[:user_id].present?
      @audits = @audits.where(created_at: ..Date.parse(params[:created_at_before])) if params[:created_at_before].present?
      @audits = @audits.where(created_at: Date.parse(params[:created_at_after])..) if params[:created_at_after].present?
      @audits = @audits.order("id desc").page params[:page]      
    end
  end
  