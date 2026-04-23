module ReportsHelper
  def with_frame(frame_name)
    if params[:report_id].present?
      "report_#{params[:report_id]}"
    elsif params[:widget_id].present?
      "#{frame_name}_#{params[:widget_id]}"
    else
      frame_name
    end
  end
end
