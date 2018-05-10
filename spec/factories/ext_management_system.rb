FactoryGirl.define do
  factory :ems_google_with_vcr_authentication, :parent => :ems_google do
    zone do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      zone
    end

    after(:create) do |ems|
      project         = Rails.application.secrets.google.try(:[], 'project') || 'GOOGLE_PROJECT'
      service_account = Rails.application.secrets.google.try(:[], 'service_account') || 'GOOGLE_SERVICE_ACCOUNT'

      ems.authentications << FactoryGirl.create(
        :authentication,
        :type     => "AuthToken",
        :auth_key => service_account,
        :userid   => "_"
      )
      ems.update_attributes(:project => project)
    end
  end
end
