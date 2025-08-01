class SkincareAnalysis < ApplicationRecord
  belongs_to :user, optional: true
  validates :image_url, presence: true
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" }

  after_destroy :delete_image_from_backblaze

  def delete_image_from_backblaze
    return unless image_url.present?
    delete_from_backblaze
  end
end