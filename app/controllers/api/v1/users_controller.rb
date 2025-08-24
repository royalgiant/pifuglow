class Api::V1::UsersController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create, :destroy], if: -> { 
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

    # Calculate health scores for the last 7 days
    overall_skin_health_score = calculate_overall_skin_health_score(user)
    weekly_skin_health_score = calculate_weekly_skin_health_score(user)
    weekly_meal_health_score = calculate_weekly_meal_health_score(user)

    render json: {
      user: {
        id: user.id,
        email: user.email,
        first_name: user.first_name,
        last_name: user.last_name,
        current_products: user.current_products,
        skin_problem: user.skin_problem,
        overall_skin_health_score: overall_skin_health_score,
        weekly_skin_health_score: weekly_skin_health_score,
        weekly_meal_health_score: weekly_meal_health_score
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

    params_with_full_name = user_settings_params.tap do |p|
      p[:full_name] = "#{p[:first_name]} #{p[:last_name]}"
    end

    if user.update(params_with_full_name)
      # Calculate health scores for the updated user
      overall_skin_health_score = calculate_overall_skin_health_score(user)
      weekly_skin_health_score = calculate_weekly_skin_health_score(user)
      weekly_meal_health_score = calculate_weekly_meal_health_score(user)

      render json: {
        message: 'Settings updated successfully. If you updated your email, please confirm your email.',
        user: {
          id: user.id,
          email: user.email,
          first_name: user.first_name,
          last_name: user.last_name,
          current_products: user.current_products,
          skin_problem: user.skin_problem,
          overall_skin_health_score: overall_skin_health_score,
          weekly_skin_health_score: weekly_skin_health_score,
          weekly_meal_health_score: weekly_meal_health_score
        }
      }, status: :ok
    else
      render json: {
        message: 'Failed to update settings',
        errors: user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    begin
      user = User.find(params[:id])
      
      if user.destroy
        render json: {
          message: 'Account deleted successfully'
        }, status: :ok
      else
        render json: {
          message: 'Failed to delete account',
          errors: user.errors.full_messages
        }, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordNotFound
      render json: {
        message: 'User not found',
        error: 'No user found with that ID'
      }, status: :not_found
    rescue StandardError => e
      Rails.logger.error("Failed to delete user: #{e.message}")
      render json: {
        message: 'Failed to delete account',
        error: 'An unexpected error occurred'
      }, status: :internal_server_error
    end
  end

  private

  def user_settings_params
    params.require(:user).permit(:email, :first_name, :last_name, :current_products, :skin_problem, :full_name)
  end

  def health_score_base_query(user)
    week_ago = 7.days.ago
    user.skincare_analysis
      .where(created_at: week_ago..Time.current)
      .where.not(diagnosis: [nil, ''])
      .where("diagnosis::jsonb ? 'skin_health'")
  end

  def calculate_overall_skin_health_score(user)
    week_ago = 7.days.ago
    sql = <<~SQL
      SELECT AVG(CAST(SPLIT_PART(diagnosis::jsonb->>'skin_health', '/', 1) AS FLOAT)) as avg_score 
      FROM skincare_analyses 
      WHERE user_id = $1 
        AND created_at BETWEEN $2 AND $3
        AND diagnosis IS NOT NULL 
        AND diagnosis != '' 
        AND diagnosis::jsonb ? 'skin_health'
    SQL
    
    result = ActiveRecord::Base.connection.exec_query(sql, 'calculate_overall_skin_health_score', [
      user.id,
      week_ago,
      Time.current
    ]).first
    result&.dig('avg_score')&.to_f&.ceil
  end

  def calculate_weekly_skin_health_score(user)
    week_ago = 7.days.ago
    sql = <<~SQL
      SELECT AVG(CAST(SPLIT_PART(diagnosis::jsonb->>'skin_health', '/', 1) AS FLOAT)) as avg_score 
      FROM skincare_analyses 
      WHERE user_id = $1 
        AND created_at BETWEEN $2 AND $3
        AND diagnosis IS NOT NULL 
        AND diagnosis != '' 
        AND diagnosis::jsonb ? 'skin_health'
        AND category = $4
    SQL
    
    result = ActiveRecord::Base.connection.exec_query(sql, 'calculate_weekly_skin_health_score', [
      user.id,
      week_ago,
      Time.current,
      'skin'
    ]).first
    result&.dig('avg_score')&.to_f&.ceil
  end

  def calculate_weekly_meal_health_score(user)
    week_ago = 7.days.ago
    sql = <<~SQL
      SELECT AVG(CAST(SPLIT_PART(diagnosis::jsonb->>'skin_health', '/', 1) AS FLOAT)) as avg_score 
      FROM skincare_analyses 
      WHERE user_id = $1 
        AND created_at BETWEEN $2 AND $3
        AND diagnosis IS NOT NULL 
        AND diagnosis != '' 
        AND diagnosis::jsonb ? 'skin_health'
        AND category = $4
    SQL
    
    result = ActiveRecord::Base.connection.exec_query(sql, 'calculate_weekly_meal_health_score', [
      user.id,
      week_ago,
      Time.current,
      'meal'
    ]).first
    result&.dig('avg_score')&.to_f&.ceil
  end
end