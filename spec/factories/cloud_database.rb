FactoryBot.define do
  factory :cloud_database_google,
          :class => "ManageIQ::Providers::Google::CloudManager::CloudDatabase"
end
