# frozen_string_literal: true

# Recording Studio 4.2 default_layout passes PageNav `anchor_url:`.
# FlatPack 0.1.143 PageNav reads `anchor_href:`. Alias without forking the layout.
module DummyFlatPackPageNavAnchorUrl
  def initialize(anchor_url: nil, **kwargs)
    kwargs[:anchor_href] = kwargs[:anchor_href].presence || anchor_url
    super(**kwargs)
  end
end

Rails.application.config.to_prepare do
  next unless defined?(FlatPack::PageNav::Component)
  next if FlatPack::PageNav::Component < DummyFlatPackPageNavAnchorUrl

  FlatPack::PageNav::Component.prepend(DummyFlatPackPageNavAnchorUrl)
end
