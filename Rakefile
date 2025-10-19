# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

require "standard/rake"

require "rake/extensiontask"

task build: :compile

GEMSPEC = Gem::Specification.load("vibe_zstd.gemspec")

Rake::ExtensionTask.new("vibe_zstd", GEMSPEC) do |ext|
  ext.lib_dir = "lib/vibe_zstd"
end

task default: %i[clobber compile test standard]
