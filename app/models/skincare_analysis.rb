class SkincareAnalysis < ApplicationRecord
  belongs_to :user, optional: true
  validates :image_url, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" }


  def delete_backblaze_object_from_url
    return unless image_url.present?
  
    bucket_name = Rails.application.credentials.dig(Rails.env.to_sym, :backblaze, :bucket_name)
    object_key = image_url.split("https://f005.backblazeb2.com/file/#{bucket_name}/").last
  
    s3_client.delete_object(
      bucket: bucket_name,
      key: object_key
    )
  rescue StandardError => e
    Rails.logger.error("Failed to delete Backblaze object: #{e.message}")
  end
end