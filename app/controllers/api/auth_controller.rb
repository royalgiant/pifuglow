class Api::AuthController < ApplicationController
  skip_before_action :verify_authenticity_token
  
  def social
    begin
      user_params = params.require(:user).permit(:email, :name, :provider, :provider_uid)
      
      # Try to find existing identity
      identity = UserIdentity.find_by(
        provider: user_params[:provider], 
        uid: user_params[:provider_uid]
      )
      
      if identity
        # Found existing identity, use that user
        user = identity.user
        
        # Update email if it's missing (Apple case)
        if user_params[:email].present? && user.email.blank?
          user.update(email: user_params[:email])
        end
        
        render json: { 
          success: true, 
          user: user_response(user),
          message: 'Signed in successfully'
        }, status: :ok
      else
        # No existing identity found
        user = nil
        
        # Try to find user by email if provided
        if user_params[:email].present?
          user = User.find_by(email: user_params[:email])
        end
        
        if user.nil?
          # Create new user
          name_parts = user_params[:name]&.split(' ', 2) || []
          
          # Handle Apple's "null null" case
          if user_params[:name] == "null null" || user_params[:name].blank?
            first_name = 'Apple'
            last_name = 'User'
            full_name = 'Apple User'
          else
            first_name = name_parts[0] || ''
            last_name = name_parts[1] || ''
            full_name = user_params[:name]
          end
          
          email = user_params[:email].present? ? user_params[:email] : "apple_#{user_params[:provider_uid].gsub('.', '_')}@tempuser.app"

          user = User.new(
            first_name: first_name,
            last_name: last_name,
            full_name: full_name,
            email: email,
            password: Devise.friendly_token[0, 20],
          )
          
          if user.save
            # Create identity for new user
            user.user_identities.create!(
              provider: user_params[:provider],
              uid: user_params[:provider_uid]
            )
            
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
          # Existing user found by email, add new identity
          user.user_identities.create!(
            provider: user_params[:provider],
            uid: user_params[:provider_uid]
          )
          
          render json: { 
            success: true, 
            user: user_response(user),
            message: 'Account linked successfully'
          }, status: :ok
        end
      end
      
    rescue ActiveRecord::RecordInvalid => e
      render json: { 
        success: false, 
        error: "Failed to create identity: #{e.message}" 
      }, status: :unprocessable_entity
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
      created_at: user.created_at
    }
  end
end