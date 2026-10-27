# frozen_string_literal: true

# Recording Studio Admin v2.2 still builds FlatPack::PageNav with the
# keywords Flatpack 0.1.319 removed. Translate those into with_back,
# with_close, and a right slot so admin screens keep rendering.
module DummyFlatPackPageNavLegacyKeywords
  REMOVED = %i[
    show_back
    right_slot
    back_href
    back_icon
    back_tooltip
    back_label
    back_style
    back_size
    anchor_href
    anchor_icon
    anchor_tooltip
    anchor_label
    anchor_style
    anchor_size
    anchor_url
  ].freeze

  def initialize(**kwargs)
    legacy = kwargs.extract!(*REMOVED)
    secondary_keys = kwargs.keys.grep(/\Asecondary_anchor/)
    secondary = kwargs.extract!(*secondary_keys)
    super(**kwargs)
    apply_legacy_page_nav(legacy, secondary)
  end

  def right_slot(&block)
    remember { capture(&block) }
  end

  private

  def apply_legacy_page_nav(legacy, secondary)
    back_href = secondary[:secondary_anchor_href] || legacy[:back_href]
    if back_href.present? || legacy[:back_label].present? || legacy[:back_tooltip].present?
      with_back(
        href: back_href,
        icon: legacy[:back_icon],
        tooltip: legacy[:back_label] || legacy[:back_tooltip],
        style: legacy[:back_style],
        size: legacy[:back_size]
      )
    end

    anchor = legacy[:anchor_href] || legacy[:anchor_url]
    return if anchor.blank?

    with_close(
      href: anchor,
      icon: legacy[:anchor_icon],
      tooltip: legacy[:anchor_label] || legacy[:anchor_tooltip],
      style: legacy[:anchor_style],
      size: legacy[:anchor_size]
    )
  end
end

Rails.application.config.to_prepare do
  next unless defined?(FlatPack::PageNav::Component)
  next if FlatPack::PageNav::Component < DummyFlatPackPageNavLegacyKeywords

  FlatPack::PageNav::Component.prepend(DummyFlatPackPageNavLegacyKeywords)
end
