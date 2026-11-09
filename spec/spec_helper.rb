if ENV['CI']
  require 'simplecov'
  SimpleCov.start
end

Dir[Rails.root.join("spec/shared/**/*.rb")].each { |f| require f }
Dir[File.join(__dir__, "support/**/*.rb")].each { |f| require f }

require "manageiq/providers/google"

VCR.configure do |config|
  config.ignore_hosts 'codeclimate.com' if ENV['CI']
  config.cassette_library_dir = File.join(ManageIQ::Providers::Google::Engine.root, 'spec/vcr_cassettes')

  VcrSecrets.define_all_cassette_placeholders(config, :google)
  VcrSecrets.define_all_cassette_placeholders(config, :google_gke)

  # Never record real OAuth bearer tokens in cassettes
  config.before_record do |interaction|
    auth = interaction.request.headers["Authorization"]
    auth&.map! { |value| value.sub(/\ABearer\s+\S+/, "Bearer BEARER_TOKEN") }
  end
end
