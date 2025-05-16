module WithBulkActions
  extend ActiveSupport::Concern

  # This is a common action for all models which have filters. Bulk actions can be applied to filtered results. A Job "#{controller_name}BulkActionJob", needs to be defined, which will be passed the ids of the filtered results. and the bulk action to perform on them. Note that the controller must implement a fetch_rows method which returns the filtered results.
  def bulk_actions
    # Here we get a ransack search
    rows = fetch_rows

    # and a bulk action to perform on the results
    bulk_action_job = if params[:bulk_action_job_prefix].blank?
                        # The specific bulk action job is passed as a parameter
                        "#{params[:bulk_action_job_prefix]}_#{controller_name}_bulk_action_job".classify.constantize
                      else
                        # The Default bulk action job is the controller name suffixed with BulkActionJob
                        "#{controller_name}_bulk_action_job".classify.constantize
                      end

    bulk_action_job.perform_later(rows.pluck(:id), current_user.id, params[:bulk_action], params: params.to_unsafe_h)

    # and redirect back to the page we came from
    redirect_path = request.referer || root_path
    redirect_to redirect_path, notice: "Bulk Action started, please check back in a few mins."
  end
end
