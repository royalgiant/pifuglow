class Api::V1::ErrorLogsController < ApplicationController
  def create
    error_log = ErrorLog.log_error(
      context: error_params[:context],
      error_message: error_params[:error_message],
      error_code: error_params[:error_code],
      metadata: error_params[:metadata] || {}
    )

    render json: { 
      success: true, 
      error_log_id: error_log.id 
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { 
      success: false, 
      error: e.record.errors.full_messages 
    }, status: :unprocessable_entity
  rescue => e
    Rails.logger.error "Failed to log error: #{e.message}"
    render json: { 
      success: false, 
      error: 'Failed to log error' 
    }, status: :internal_server_error
  end

  private

  def error_params
    params.require(:error).permit(:context, :error_message, :error_code, metadata: {})
  end
end