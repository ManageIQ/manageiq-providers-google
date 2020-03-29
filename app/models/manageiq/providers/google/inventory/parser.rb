class ManageIQ::Providers::Google::Inventory::Parser < ManageIQ::Providers::Inventory::Parser
  require_nested :CloudManager
  require_nested :NetworkManager

  VENDOR_GOOGLE = "google".freeze

  def parse_uid_from_url(url)
    # A lot of attributes in gce are full URLs with the
    # uid being the last component.  This helper method
    # returns the last component of the url
    url.split('/')[-1]
  end
end
