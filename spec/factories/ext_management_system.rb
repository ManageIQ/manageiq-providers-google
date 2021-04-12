FactoryBot.define do
  factory :ems_google_with_vcr_authentication, :parent => :ems_google, :traits => [:with_zone] do
    after(:create) do |ems|
      project         = Rails.application.secrets.google[:project]
      service_account = Rails.application.secrets.google[:service_account]

      ems.authentications << FactoryBot.create(
        :authentication,
        :type     => "AuthToken",
        :auth_key => service_account,
        :userid   => "_"
      )
      ems.update(:project => project)
    end
  end

  factory :ems_google_with_project, :parent => :ems_google_with_authentication, :traits => [:with_zone] do
    project { 'GOOGLE_PROJECT' }
  end

  trait :with_zone do
    zone do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      zone
    end
  end
end
