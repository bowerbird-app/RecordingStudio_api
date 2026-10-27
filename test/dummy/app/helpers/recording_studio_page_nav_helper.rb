# frozen_string_literal: true

# Recording Studio Admin v2.2 still calls the helper removed in
# Recording Studio v5. Translate its back and close URLs into the
# Flatpack page nav the default layout renders.
module RecordingStudioPageNavHelper
  def recording_studio_page_nav(**options)
    kwargs = {round: true, style: :default}
    back_url = options[:page_nav_back_url]
    anchor_url = options[:page_nav_anchor_url]

    if back_url.present?
      kwargs[:back_href] = back_url
      kwargs[:back_tooltip] = options[:page_nav_back_label].presence || "Back"
    end

    if anchor_url.present?
      kwargs[:anchor_href] = anchor_url
      kwargs[:anchor_tooltip] = options[:page_nav_anchor_label].presence || "Close"
    end

    flat_pack_page_nav(**kwargs) if kwargs.key?(:back_href) || kwargs.key?(:anchor_href)
    nil
  end
end
