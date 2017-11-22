describe :placeholders do
  include_examples :placeholders, ManageIQ::Providers::Google::Engine.root.join('locale').to_s
end
