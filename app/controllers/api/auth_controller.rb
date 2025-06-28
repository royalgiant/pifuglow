# app/controllers/api/auth_controller.rb
class Api::AuthController < ApplicationController
  skip_before_action :verify_authenticity_token
  
  def social
    begin
      user_params = params.require(:user).permit(:email, :name, :provider, :provider_uid)
      
      user = User.find_or_initialize_by(email: user_params[:email])
      
      if user.new_record?
        # New user
        name_parts = user_params[:name].split(' ', 2)
        first_name = name_parts[0] || ''
        last_name = name_parts[1] || ''
        user.assign_attributes(
          first_name: first_name,
          last_name: last_name,
          full_name: user_params[:name],
          provider: user_params[:provider],
          uid: user_params[:provider_uid],
          password: Devise.friendly_token[0, 20]
        )
        
        if user.save
          render json: { 
            success: true, 
            user: user_response(user),
            message: 'Account created successfully'
          }, status: :created
        else
          render json: { 
            success: false, 
            errors: user.errors.full_messages 
          }, status: :unprocessable_entity
        end
      else
        if user.provider != user_params[:provider]
          user.update(
            provider: user_params[:provider],
            uid: user_params[:provider_uid]
          )
        end
        
        render json: { 
          success: true, 
          user: user_response(user),
          message: 'Signed in successfully'
        }, status: :ok
      end
      
    rescue ActionController::ParameterMissing => e
      render json: { 
        success: false, 
        error: "Missing required parameter: #{e.param}" 
      }, status: :bad_request
    rescue => e
      Rails.logger.error "Social auth error: #{e.message}"
      render json: { 
        success: false, 
        error: 'Authentication failed. Please try again.' 
      }, status: :internal_server_error
    end
  end
  
  private
  
  def user_response(user)
    {
      id: user.id,
      email: user.email,
      name: user.full_name,
      provider: user.provider
    }
  end
end