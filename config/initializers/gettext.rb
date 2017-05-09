Vmdb::Gettext::Domains.add_domain(
  'ManageIQ_Providers_Google',
  ManageIQ::Providers::Google::Engine.root.join('locale').to_s,
  :po
)
