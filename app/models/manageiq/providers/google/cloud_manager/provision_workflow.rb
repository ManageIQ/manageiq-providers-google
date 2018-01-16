class ManageIQ::Providers::Google::CloudManager::ProvisionWorkflow < ::MiqProvisionCloudWorkflow
  def allowed_instance_types(_options = {})
    source = load_ar_obj(get_source_vm)
    ems = get_targets_for_ems(source, :cloud_filter, Flavor, 'flavors')
    ems.each_with_object({}) { |f, h| h[f.id] = display_name_for_name_description(f) }
  end

  def allowed_cloud_networks(_options = {})
    return {} unless (src_obj = provider_or_tenant_object)

    src_obj.all_cloud_networks.each_with_object({}) do |cn, hash|
      hash[cn.id] = cn.cidr.blank? ? cn.name : "#{cn.name} (#{cn.cidr})"
    end
  end

  private

  def dialog_name_from_automate(message = 'get_dialog_name')
    super(message, {'platform' => 'google'})
  end

  def self.provider_model
    ManageIQ::Providers::Google::CloudManager
  end
end
