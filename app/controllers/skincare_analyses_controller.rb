class SkincareAnalysesController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create], if: -> { 
    request.format.json? || mobile_request?
  }
  def new
    @skincare_analysis = SkincareAnalysis.new
    respond_to do |format|
      format.html
      format.json { render json: { message: "Use POST to /skincare_analyses to submit an image" }, status: :ok }
    end
  end

  def create
    request.format = :json if mobile_request?
    recent_analysis = SkincareAnalysis.where(email: skincare_analysis_params[:email]).order(created_at: :desc).first
    @skincare_analysis = SkincareAnalysis.new(skincare_analysis_params)

    if recent_analysis && recent_analysis.created_at > 7.days.ago
      respond_to do |format|
        format.html do
          flash[:notice] = "You can only get a free skin analysis every 7 days. Please come back in a week!"
          redirect_to root_path
        end
        format.json { render json: { error: "You can only get a free skin analysis every 7 days. Please try again later." }, status: :too_many_requests }
      end
      return
    end

    if @skincare_analysis.valid?
      image_url = handle_image_processing(skincare_analysis_params)
      if image_url
        @skincare_analysis.image_url = image_url
        user = User.find_by(email: skincare_analysis_params[:email])
        @skincare_analysis.user_id = user.id
        if @skincare_analysis.save
          begin
            analysis_result = OpenaiAnalysisService.new.analyze_image(image_url)
            @skincare_analysis.update!(diagnosis: analysis_result[:diagnosis])
            send_analysis_email(@skincare_analysis.email, analysis_result[:diagnosis], image_url) if !mobile_request?
            respond_to do |format|
              format.html do
                flash[:success] = "Image uploaded successfully. Please check your email for your analysis."
                redirect_to root_path
              end
              format.json do
                render json: { 
                  message: "Analysis completed successfully",
                  diagnosis: analysis_result[:diagnosis],
                  image_url: image_url
                }, status: :created
              end
            end
          rescue StandardError => e
            Rails.logger.error("OpenAI analysis failed: #{e.message}")
            send_analysis_email(@skincare_analysis.email, "Analysis failed. We’ll retry later.", image_url)
            respond_to do |format|
              format.html do
                flash[:success] = "Image uploaded successfully, but analysis failed. We’ll send the analysis to your email later."
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
        else
          respond_to do |format|
            format.html do
              flash[:error] = @skincare_analysis.errors.full_messages.join(", ")
              render :new, status: :unprocessable_entity
            end
            format.json { render json: { error: @skincare_analysis.errors.full_messages.join(", ") }, status: :unprocessable_entity }
          end
        end
      else
        @skincare_analysis.errors.add(:image_url, "failed to upload. Please try again.")
        respond_to do |format|
          format.html do
            flash[:error] = @skincare_analysis.errors.full_messages.join(", ")
            render :new, status: :unprocessable_entity
          end
          format.json { render json: { error: @skincare_analysis.errors.full_messages.join(", ") }, status: :unprocessable_entity }
        end
      end
    else
      respond_to do |format|
        format.html do
          flash[:error] = @skincare_analysis.errors.full_messages.join(", ")
          render :new, status: :unprocessable_entity
        end
        format.json { render json: { error: @skincare_analysis.errors.full_messages.join(", ") }, status: :unprocessable_entity }
      end
    end
  end

  private

  def skincare_analysis_params
    params.require(:skincare_analysis).permit(:image_url, :email)
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

  def mobile_request?
    request.headers['X-Mobile-App'] == 'true'
  end

  def send_analysis_email(email, diagnosis, image_url)
    Rails.logger.info "Sending analysis email to #{email} with diagnosis: #{diagnosis.truncate(100)}"
    SkincareAnalysisMailer.with(email: email, diagnosis: diagnosis, image_url: image_url).analysis_result.deliver_now
  end
end