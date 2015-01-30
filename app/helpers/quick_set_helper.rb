module QuickSetHelper

  def tooltip(quickset)
    return unless quickset and quickset.content_providers.size > 0

    tooltip = ''
    quickset.content_providers.each do |db|
      tooltip += db.name
    end

    tooltip
  end

  def quickset_popover_data_options(quickset)
    return unless quickset and quickset.content_providers.size > 0

    data_options = {
      title:     quickset.name,
      toggle:    'popover',
      trigger:   'hover',
      # trigger:   'click',
      html:      'true',
      placement: 'top',
      content:   popover_content(quickset)
    }

    return data_options
  end


  def popover_content(quickset)
    return unless quickset && quickset.content_providers.size > 0

    popover_content = "<b>Set contains #{quickset.content_providers.size} databases</b>"

    popover_content += "<ul class='quickset_database'>"
    quickset.content_providers.each do |db|
      popover_content += "<li>#{db.name}</li>"
    end
    popover_content += "</ul>"

    popover_content
  end

end
