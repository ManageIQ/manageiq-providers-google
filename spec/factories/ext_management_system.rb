FactoryGirl.define do
  factory :ems_google_with_vcr_authentication, :parent => :ems_google, :traits => [:with_zone] do
    after(:create) do |ems|
      project         = Rails.application.secrets.google.try(:[], 'project') || 'GOOGLE_PROJECT'

      # If service account JSON is not available in secrets provide a dummy JSON with fake cetrificare
      service_account = Rails.application.secrets.google.try(:[], 'service_account') || <<-GOOGLE_SERVICE_ACCOUNT
      {
        "type": "service_account",
        "project_id": "GOOGLE_PROJECT",
        "private_key_id": "1111111111111111111111111111111111111111",
        "private_key": "-----BEGIN RSA PRIVATE KEY-----\\nMIIEowIBAAKCAQEApY2Hv2jiSyzDvowhxVlUVZtDAguKJB7/NE3MOBZ+k6ER3rEu\\n5hJNu1TxVPj1dXcTIyKX7X5ipmqVQPyrZHd6ec8RVPlzEWfCF3Yew0qJ/8dIVI6e\\n//5JheSzabeGKx8v89K0Tso4b7WYInomFNKs35LQHLOtF1L0P8z2S44/0K02wzeO\\n3YhFM3MEONX7LOaYERheX9vFmjBI3UoO2twSScKAVB4N+y4bQgyTKcUNDbYW0TOm\\n673YBfjPLbKomr5t1C+A/Jn/pCd4oQy+k3GtlQYjLsJ8BabbKZtuCCExOno64loJ\\ntIqlKFo4hyB3MAYFNBvSLvgzX2OI/3OVX7e//QIDAQABAoIBACXHwq7f1KSrNpCJ\\nkjtjQ2e14vjYgVH08PCSwIQcPg6at2VGshk3HB4gKGLn3bxMzEU8Y8eDDChGMoF+\\nJ+7phT2/D4mA082pDBYmkqamoA+K/uqtEYQCF+1CX99ETo4Qs/TEpPlGFNMJcgqM\\nLZya53CuJGgoaNvlxm+46owbjlykjLQOlOpwvf0HSFwsOlOPFPn1YbWtUMV2XJj4\\n4haCP7QwrZiqct4CQZ7zowmoQH/u0akhQylK5HpUJETzrVrSHYwvcvWmu+HAlx5l\\n4YWrunCxjc7eT6cOFig887FOSfAkO5bbNvDlduNn4FYKLS7z2tuZGAh8Bme4Gf8P\\n8XIKowECgYEA2sGyEV+z3f793u1qy9E1Q/6K8BeC62NekOVePcGcnVxGGYqiiaWn\\nemmqOBcyLSYrdBfqo/4zoZke7QmPKlCVg4Uv8g2VXx/wUbW7yE5pWiqn/vpT9zV0\\ndJWy56LQNUo2e2BBL9PaU1UU93RLem3vyPf1KxADXZ8Fu63YIGzFSI0CgYEAwbz/\\nagd9Th2RVJ1uxV/G0Wstce1wXQILrONbBivdgqXcxe8SBDk6xcwJ3JdGoiTDXjBM\\n1zOvFhZvPCg/Y3nkB9jf8ORO41UaCdZ8KpYlJhUxu04sZ43j/BIteRMNjnxhZix2\\n9pBNC6GVkiy89/IzpTR7w6UVTrzmbw2nf5iRkTECgYBTV0gH5nYYNXVy4PC3BdVN\\nOkSkg9CU7R6yBTCKRqDsMqNiR7b0ye+sa2U2SWAMY2ZarGHwaIAzKKrnk6S/ckQD\\n/1Hs3c/ylbBw8NPB1F2+xFGMisJChFMBt6aZKSY5pzRqfJlZJ1UeOmPqgpve4NNh\\ntVXqOgeOO29ruSeF8uqWYQKBgQCMga+TjD76akM+ZLczehTNSLe6yoMVUSh6iKE5\\nRpLt77C/9HTSj1bqoOH+E9BsQ9FU/B6ebKNsl3Sw4lemo34Xmtg+8rWr9cpenCmN\\nETt79R8OQtG9gJB5/gzwpDrOvbI90b2tcFYQO24ohz29bPC7veaMq6taYXGV1QdH\\naLUZ4QKBgE/0lK/uRiAxbdRu9bEdq8eZpTick6dmey4rBLnB5yg7vATUZnRf5yuF\\njUNlWziC5y4XsOpAuAUgRi8NqSUHRhmZ8ecjaoFo1xUVifW4knuw/9Ikq+2UyN/Z\\nBy0ccuzCmppA8QoeQ86xPd6u+vCn1o4OaG+uSW7j5/GKXrUinMMb\\n-----END RSA PRIVATE KEY-----\\n",
        "client_email": "11111111111-compute@developer.gserviceaccount.com",
        "client_id": "111111111111111111111"
      }
      GOOGLE_SERVICE_ACCOUNT

      ems.authentications << FactoryGirl.create(
        :authentication,
        :type     => "AuthToken",
        :auth_key => service_account,
        :userid   => "_"
      )
      ems.update_attributes(:project => project)
    end
  end

  factory :ems_google_with_project, :parent => :ems_google_with_authentication, :traits => [:with_zone] do
    project 'GOOGLE_PROJECT'
  end

  trait :with_zone do
    zone do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      zone
    end
  end
end
