class SkincareAnalysesController < ApplicationController
  def new
    @skincare_analysis = SkincareAnalysis.new
  end

  def create
    @skincare_analysis = SkincareAnalysis.new(skincare_analysis_params)
    if @skincare_analysis.valid?
      image_url = handle_image_processing(skincare_analysis_params)
      if image_url
        @skincare_analysis.image_url = image_url
        if @skincare_analysis.save
          # Analyze the image with Claude and update the diagnosis
          begin
            analysis_result = ClaudeAnalysisService.new.analyze_image(image_url)
            @skincare_analysis.update!(diagnosis: analysis_result[:diagnosis])
            # Notify user via email (placeholder for email sending logic)
            send_analysis_email(@skincare_analysis.email, analysis_result[:diagnosis])
            flash[:success] = "Image uploaded successfully. Please check your email for your analysis."
            redirect_to root_path
          rescue StandardError => e
            Rails.logger.error("Claude analysis failed: #{e.message}")
            flash[:success] = "Image uploaded successfully, but analysis failed. We’ll send the analysis to your email later."
            redirect_to root_path
          end
        else
          flash[:error] = @skincare_analysis.errors.full_messages.join(", ")
          render :new, status: :unprocessable_entity
        end
      else
        @skincare_analysis.errors.add(:image_url, "failed to upload. Please try again.")
        flash[:error] = @skincare_analysis.errors.full_messages.join(", ")
        render :new, status: :unprocessable_entity
      end
    else
      flash[:error] = @skincare_analysis.errors.full_messages.join(", ")
      render :new, status: :unprocessable_entity
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

  def send_analysis_email(email, diagnosis)
    Rails.logger.info "Sending analysis email to #{email} with diagnosis: #{diagnosis.truncate(100)}"
    SkincareAnalysisMailer.with(email: email, diagnosis: diagnosis).analysis_result.deliver_now
  end
end