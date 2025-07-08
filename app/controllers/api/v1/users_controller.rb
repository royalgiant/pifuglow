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
    user = User.find_by(email: params[:email])
    
    if user.nil?
      render json: {
        message: 'User not found',
        error: 'No user found with that email address'
      }, status: :not_found
      return
    end

    if user.update(user_settings_params)
      render json: {
        message: 'Settings updated successfully',
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