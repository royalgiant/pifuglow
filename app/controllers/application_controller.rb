class ApplicationController < ActionController::Base
  
  private

  def authorize_user!(record)
    unless record&.user == current_user
      flash[:alert] = "You are not authorized to perform this action."
      redirect_to root_path
    end
  end
end
