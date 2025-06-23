Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins Rails.env.production? ? ['pifuglow.com', 'https://pifuglow.com', ->(origin) { origin.nil? }] : '*'
    resource '/skincare_analyses*', headers: :any, methods: [:get, :post]
  end
end