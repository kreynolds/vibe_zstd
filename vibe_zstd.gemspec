# frozen_string_literal: true

require_relative "lib/vibe_zstd/version"

Gem::Specification.new do |spec|
  spec.name = "vibe_zstd"
  spec.version = VibeZstd::VERSION
  spec.authors = ["Kelley Reynolds"]
  spec.email = ["kelley@water5000.com"]

  spec.summary = "Ruby bindings for Zstandard compression"
  spec.description = "Fast, idiomatic Ruby bindings for Zstandard (zstd) compression library"
  spec.homepage = "https://github.com/kreynolds/vibe_zstd"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/kreynolds/vibe_zstd"
  spec.metadata["changelog_uri"] = "https://github.com/kreynolds/vibe_zstd/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/vibe_zstd/extconf.rb"]

  # Development dependencies
  spec.add_development_dependency "benchmark-ips", "~> 2.0"
  spec.add_development_dependency "terminal-table", "~> 3.0"
end
