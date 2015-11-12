class QuickSet < ActiveRecord::Base
  has_and_belongs_to_many :content_providers
  attr_accessible :name, :description, :suppressed, :content_provider_ids

  def content_provider_names
    self.content_providers.collect do |content_provider|
      content_provider.name
    end.sort_by!{ |name| name.downcase }
  end

end
