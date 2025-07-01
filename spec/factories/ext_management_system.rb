FactoryBot.define do
  factory :ems_google_with_vcr_authentication, :parent => :ems_google, :traits => [:with_zone] do
    after(:create) do |ems|
      project         = VcrSecrets.google.project
      service_account = VcrSecrets.google.service_account

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

  factory :ems_google_gke,
          :aliases => ["manageiq/providers/google/container_manager"],
          :class   => "ManageIQ::Providers::Google::ContainerManager",
          :parent  => :ems_container do
    security_protocol { "ssl-without-validation" }
    port { 443 }
  end

  factory :ems_google_gke_with_vcr_authentication, :parent => :ems_google_gke, :traits => %i[with_zone] do
    project { VcrSecrets.google_gke.project }
    hostname { "34.71.86.84" }

    after(:create) do |ems|
      ems.authentications << FactoryBot.create(
        :authentication,
        :type     => "AuthToken",
        :authtype => "bearer",
        :auth_key => VcrSecrets.google_gke.service_account,
        :userid   => "_"
      )
    end
  end

  trait :with_zone do
    zone do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      zone
    end
  end
end
