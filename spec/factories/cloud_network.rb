FactoryBot.define do
  factory :cloud_network_google,
          :class  => "ManageIQ::Providers::Google::NetworkManager::CloudNetwork",
          :parent => :cloud_network
end
