require "fileutils"

namespace :flat_pack do
  desc "Prepare FlatPack stylesheets for the dummy app Tailwind build"
  task prepare_tailwind_assets: :environment do
    next unless defined?(FlatPack::Engine)

    source_dir = FlatPack::Engine.root.join("app/assets/stylesheets/flat_pack")
    target_dir = Rails.root.join("app/assets/tailwind/flat_pack")

    FileUtils.mkdir_p(target_dir)

    %w[variables.css rich_text.css content_editor.css].each do |filename|
      FileUtils.cp(source_dir.join(filename), target_dir.join(filename))
    end

    application_css = source_dir.join("application.css").read
      .gsub('"flat_pack/variables.css"', '"./variables.css"')
      .gsub('"flat_pack/rich_text.css"', '"./rich_text.css"')
      .gsub('"flat_pack/content_editor.css"', '"./content_editor.css"')

    target_dir.join("application.css").write(application_css)
  end
end

%w[tailwindcss:build tailwindcss:watch].each do |task_name|
  next unless Rake::Task.task_defined?(task_name)

  Rake::Task[task_name].enhance(["flat_pack:prepare_tailwind_assets"])
end