class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  def s3_client
		s3_client ||= Aws::S3::Client.new
  end
end
