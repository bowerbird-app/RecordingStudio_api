# frozen_string_literal: true

require_relative "support/api_dummy_helpers"

class PageTest < ActiveSupport::TestCase
  test "requires a title" do
    page = Page.new

    assert_predicate page, :invalid?
    assert_includes page.errors[:title], "can't be blank"
  end

  test "rejects blank titles" do
    page = Page.new(title: "")

    assert_predicate page, :invalid?
    assert_includes page.errors[:title], "can't be blank"
  end

  test "allows titled pages" do
    page = Page.new(title: "API guide")

    assert_predicate page, :valid?
  end
end