class Api::V1::UsersController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create], if: -> { 
    request.format.json? || mobile_request?
  }

  def get_settings
    user = User.find_by(email: params[:email])
    
    if user.nil?
      render json: {
        message: 'User not found',
        error: 'No user found with that email address'
      }, status: :not_found
      return
    end

    render json: {
      user: {
        id: user.id,
        email: user.email,
        first_name: user.first_name,
        last_name: user.last_name,
        current_products: user.current_products,
        skin_problem: user.skin_problem
      }
    }, status: :ok
  end

  def update_settings
    current_email = params[:current_email]
    
    if current_email.blank?
      render json: {
        message: 'Current email required',
        error: 'Current email address is required to update settings'
      }, status: :bad_request
      return
    end

    user = User.find_by(email: current_email)
    
    if user.nil?
      render json: {
        message: 'User not found',
        error: 'No user found with that email address'
      }, status: :not_found
      return
    end

    new_email = user_settings_params[:email]
    if new_email.present? && new_email != current_email
      existing_user = User.find_by(email: new_email)
      if existing_user.present?
        render json: {
          message: 'Email already exists',
          error: 'An account with that email address already exists'
        }, status: :unprocessable_entity
        return
      end
    end
    user_settings_params[:full_name] = "#{user_settings_params[:first_name]} #{user_settings_params[:last_name]}"
    if user.update(user_settings_params)
      render json: {
        message: 'Settings updated successfully. If you updated your email, please confirm your email.',
        user: {
          id: user.id,
          email: user.email,
          first_name: user.first_name,
          last_name: user.last_name,
          current_products: user.current_products,
          skin_problem: user.skin_problem
        }
      }, status: :ok
    else
      render json: {
        message: 'Failed to update settings',
        errors: user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def user_settings_params
    params.require(:user).permit(:email, :first_name, :last_name, :current_products, :skin_problem)
  end
end