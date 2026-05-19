# frozen_string_literal: true

require_relative "lib/symphony_ruby/version"

Gem::Specification.new do |spec|
  spec.name = "symphony-ruby"
  spec.version = SymphonyRuby::VERSION
  spec.summary = "GitHub Projects v2 orchestrator for configurable coding agents"
  spec.authors = ["NomadNest"]
  spec.files = Dir["lib/**/*.rb", "bin/*", "README.md", "WORKFLOW.md"]
  spec.bindir = "bin"
  spec.executables = ["symphony-ruby"]
  spec.required_ruby_version = ">= 3.3"
end
