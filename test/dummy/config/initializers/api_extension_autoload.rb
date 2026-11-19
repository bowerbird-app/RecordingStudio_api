# frozen_string_literal: true

# Leave this controller autoloadable. Test eager load would otherwise define
# it during boot, and the extension test would no longer see it load.
Rails.autoloaders.main.do_not_eager_load(
  Rails.root.join("app/controllers/api_extension_autoload_controller.rb")
)
