class SkincareAnalysesController < ApplicationController

  def new
    @skincare_analysis = SkincareAnalysis.new
  end

  def create
    @skincare_analysis = SkincareAnalysis.build(skincare_analysis_params)
    if @skincare_analysis.valid?
      image_url = handle_image_processing(skincare_analysis_params)
      @skincare_analysis.image_url = image_url
      if @skincare_analysis.save
        redirect_to root_path, notice: "Image uploaded successfully. Analysis in progress."
      else
        flash[:error] = @skincare_analysis.errors.full_messages.join(" ,")
        render :new, status: :unprocessable_entity
      end
    else
      flash[:error] = @skincare_analysis.errors.full_messages.join(" ,")
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
    object_key = "skincare_analyses/#{skincare_analysis_params[:email]}/#{filename}"
    bucket_name = Rails.application.credentials.dig(Rails.env.to_sym, :backblaze, :bucket_name)

    # Delete existing image if exists
    s3_client.delete_object(bucket: bucket_name, key: object_key)

    begin
      content_type = skincare_analysis_params[:image_url].content_type
      Rails.logger.info "Uploading image to Backblaze: #{filename}"
      
      File.open(skincare_analysis_params[:image_url].tempfile, 'rb') do |file|
        s3_client.put_object(
          bucket: bucket_name,
          key: object_key,
          body: file,
          content_type: content_type,
          cache_control: "public, max-age=#{6.months.to_i}"
        )
      end

      Rails.logger.info "Backblaze image upload done."
      "https://f005.backblazeb2.com/file/#{bucket_name}/#{object_key}"
    rescue StandardError => e
      Rails.logger.error("Failed to upload image to Backblaze: #{e.message}")
      nil
    end
  end
end