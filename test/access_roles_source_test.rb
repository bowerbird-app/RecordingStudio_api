# frozen_string_literal: true

require "test_helper"

class AccessRolesSourceTest < Minitest::Test
  def test_library_and_dummy_do_not_call_removed_access_roles_enum
    root = File.expand_path("..", __dir__)
    paths = Dir.chdir(root) do
      Dir.glob("{app,lib,test/dummy}/**/*.{rb,erb,md}")
    end

    offenders = paths.filter_map do |path|
      contents = File.read(File.join(root, path))
      path if contents.match?(/Access\.roles\b/) || contents.match?(/enum :role/)
    end

    assert_empty offenders, "Remove RecordingStudio::Access.roles / enum :role from: #{offenders.join(', ')}"
  end
end
