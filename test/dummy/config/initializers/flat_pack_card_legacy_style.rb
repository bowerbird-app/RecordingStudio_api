# frozen_string_literal: true

# Sibling gems still pass Card `style:`. Flatpack 0.1.319 split that into
# background and border.
module DummyFlatPackCardLegacyStyle
  def initialize(style: nil, **kwargs)
    apply_legacy_card_style(style, kwargs)
    super(**kwargs)
  end

  private

  def apply_legacy_card_style(style, kwargs)
    return if style.nil?

    case style.to_sym
    when :outlined
      kwargs[:background] = :none unless kwargs.key?(:background)
      kwargs[:border] = :default unless kwargs.key?(:border)
    when :default
      kwargs[:background] = :default unless kwargs.key?(:background)
      kwargs[:border] = :default unless kwargs.key?(:border)
    else
      kwargs[:background] = style.to_sym unless kwargs.key?(:background)
    end
  end
end

Rails.application.config.to_prepare do
  next unless defined?(FlatPack::Card::Component)
  next if FlatPack::Card::Component < DummyFlatPackCardLegacyStyle

  FlatPack::Card::Component.prepend(DummyFlatPackCardLegacyStyle)
end
