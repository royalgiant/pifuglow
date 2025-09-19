class SkincareAnalysesController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create, :destroy], if: -> { 
    request.format.json? || mobile_request?
  }

  def index
    @skincare_analyses = SkincareAnalysis.where(email: params[:email]).order(created_at: :desc)
    respond_to do |format|
      format.html # for web
      format.json { 
        render json: @skincare_analyses.map do |analysis|
          {
            id: analysis.id,
            image_url: analysis.image_url,
            created_at: analysis.created_at.strftime('%m/%d/%Y'),
            diagnosis: analysis.diagnosis,
            email: analysis.email,
            category: analysis.category
          }
        end
      }
    end
  end

  def new
    @skincare_analysis = SkincareAnalysis.new
    respond_to do |format|
      format.html
      format.json { render json: { message: "Use POST to /skincare_analyses to submit an image" }, status: :ok }
    end
  end

  def create
    request.format = :json if mobile_request?

    # Check subscription status and monthly limits
    current_user = find_user
    subscribed = ActiveModel::Type::Boolean.new.cast(params[:subscribed]) || current_user.is_lifetime? || current_user.is_admin?
    unless subscribed
      month_start = Time.current.beginning_of_month
      month_end = Time.current.end_of_month
      monthly_analysis_count = SkincareAnalysis.where(
        email: skincare_analysis_params[:email],
        created_at: month_start..month_end
      ).count
      
      if monthly_analysis_count > 10
        render_error_response("You have reached the monthly limit of scans for this month. For more scans, please upgrade to pro.")
        return
      end
    end

    today_start = Time.current.beginning_of_day
    today_end = Time.current.end_of_day
    daily_analysis_count = SkincareAnalysis.where(
      email: skincare_analysis_params[:email],
      created_at: today_start..today_end
    ).count
    
    if daily_analysis_count >= 10 && !subscribed
      render_error_response("During Beta, only 10 analyses can be ran a day")
      return
    end

    @skincare_analysis = SkincareAnalysis.new(skincare_analysis_params)
    
    if @skincare_analysis.valid?
      image_url = handle_image_processing(skincare_analysis_params)
      if image_url
        # Set all attributes before the single save
        @skincare_analysis.image_url = image_url
        @skincare_analysis.request_type = mobile_request?
        @skincare_analysis.user_id = current_user.id
        
        # Get analysis result before saving
        begin
          # Get previous analysis for subscribed users
          previous_analysis = nil
          if subscribed && current_user
            last_analysis = current_user.skincare_analysis.where(category: "skin").order(created_at: :desc).first
            if last_analysis && last_analysis.diagnosis.present?
              previous_diagnosis = JSON.parse(last_analysis.diagnosis)
              previous_analysis = {
                primary_observations: previous_diagnosis.dig("condition", "primary_observations"),
                summary: previous_diagnosis.dig("condition", "summary")
              }
            end
          end

          analysis_result = OpenaiAnalysisService.new.analyze_image(image_url, mobile_request?, current_user, subscribed, previous_analysis)
          @skincare_analysis.diagnosis = analysis_result[:diagnosis].to_json
          @skincare_analysis.category = analysis_result[:diagnosis]["category"] if mobile_request?
          
          # Single save with all data
          if @skincare_analysis.save
            # Send email only for web requests, after successful save
            send_analysis_email(@skincare_analysis.email, analysis_result[:diagnosis], image_url) unless mobile_request?
            render_success_response
          else
            render_error_response(@skincare_analysis.errors.full_messages.join(", "))
          end
          
        rescue StandardError => e
          Rails.logger.error("OpenAI analysis failed: #{e.message}")
          render_analysis_failed_response(image_url)
        end
      else
        @skincare_analysis.errors.add(:image_url, "failed to upload. Please try again.")
        render_error_response(@skincare_analysis.errors.full_messages.join(", "))
      end
    else
      render_error_response(@skincare_analysis.errors.full_messages.join(", "))
    end
  end

  def destroy
    begin
      @skincare_analysis = SkincareAnalysis.find(params[:id])
      @skincare_analysis.destroy
      
      respond_to do |format|
        format.html { redirect_to root_path, notice: "Analysis deleted successfully" }
        format.json { render json: { message: "Analysis deleted successfully" }, status: :ok }
      end
    rescue ActiveRecord::RecordNotFound
      respond_to do |format|
        format.html { redirect_to root_path, alert: "Analysis not found" }
        format.json { render json: { error: "Analysis not found" }, status: :not_found }
      end
    rescue StandardError => e
      Rails.logger.error("Failed to delete analysis: #{e.message}")
      respond_to do |format|
        format.html { redirect_to root_path, alert: "Failed to delete analysis" }
        format.json { render json: { error: "Failed to delete analysis" }, status: :internal_server_error }
      end
    end
  end

  private

  def skincare_analysis_params
    params.require(:skincare_analysis).permit(:image_url, :email, :request_type)
  end

  def handle_image_processing(skincare_analysis_params)
    return false unless skincare_analysis_params[:image_url].present?

    filename = skincare_analysis_params[:image_url].original_filename.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/(^_+|_+$)/, '')
    object_key = "skincare_analyses/#{skincare_analysis_params[:email].gsub(/[@\.]/, '')}/#{filename}"
    bucket_name = Rails.application.credentials.dig(Rails.env.to_sym, :backblaze, :bucket_name)

    # Delete existing image if exists
    s3_client.delete_object(bucket: bucket_name, key: object_key)

    begin
      content_type = skincare_analysis_params[:image_url].content_type
      Rails.logger.info "Uploading image to Backblaze: #{filename}"
      s3_client.put_object(
        bucket: bucket_name,
        key: object_key,
        body: File.open(skincare_analysis_params[:image_url].tempfile.path),
        content_type: content_type,
        cache_control: "public, max-age=#{6.months.to_i}"
      )
      Rails.logger.info "Backblaze image upload done."
      "https://f005.backblazeb2.com/file/#{bucket_name}/#{object_key}"
    rescue StandardError => e
      Rails.logger.error("Failed to upload image to Backblaze: #{e.message}")
      nil
    end
  end



  def send_analysis_email(email, diagnosis, image_url)
    Rails.logger.info "Sending analysis email to #{email} with diagnosis: #{diagnosis.truncate(100)}"
    SkincareAnalysisMailer.with(email: email, diagnosis: diagnosis, image_url: image_url).analysis_result.deliver_now
  end

  def find_user
    User.find_by(email: skincare_analysis_params[:email])
  end
  
  def render_rate_limit_error
    respond_to do |format|
      format.html do
        flash[:notice] = "You can only get a free skin analysis every 7 days. Please come back in a week!"
        redirect_to root_path
      end
      format.json { render json: { error: "You can only get a free skin analysis every 7 days. Please try again later." }, status: :too_many_requests }
    end
  end
  
  def render_success_response
    respond_to do |format|
      format.html do
        flash[:success] = "Image uploaded successfully. Please check your email for your analysis."
        redirect_to root_path
      end
      format.json do
        render json: { 
          message: "Analysis completed successfully",
          diagnosis: @skincare_analysis.diagnosis,
          image_url: @skincare_analysis.image_url,
          category: @skincare_analysis.category
        }, status: :created
      end
    end
  end
  
  def render_analysis_failed_response(image_url)
    send_analysis_email(@skincare_analysis.email, "Analysis failed. We'll retry later.", image_url) unless mobile_request?
    
    respond_to do |format|
      format.html do
        flash[:success] = "Image uploaded successfully, but analysis failed. We'll send the analysis to your email later."
        redirect_to root_path
      end
      format.json do
        render json: { 
          message: "Image uploaded, but analysis failed. Results will be emailed later.",
          image_url: image_url
        }, status: :accepted
      end
    end
  end
  
  def render_error_response(error_message)
    respond_to do |format|
      format.html do
        flash[:error] = error_message
        render :new, status: :unprocessable_entity
      end
      format.json { render json: { error: error_message }, status: :unprocessable_entity }
    end
  end
end