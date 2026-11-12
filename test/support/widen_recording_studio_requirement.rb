# frozen_string_literal: true

# Several sibling git tags still declare `recording_studio` below 5.
# Relax only a requirement that rejects the pinned release, so Bundler can
# select Recording Studio v6.3.0. `recording_studio_admin` v2.13.0 allows
# `>= 6.3.0, < 7`, so this patch leaves that gemspec alone.
module WidenRecordingStudioRequirement
  NAME = "recording_studio"
  VERSION = Gem::Version.new("6.3.0")
  REQUIREMENT = Gem::Requirement.new(">= 6.1.0")

  module SpecificationPatch
    # Return the same array `add_dependency` appends to. A copy would drop
    # every dependency while Bundler evaluates git and path gemspecs.
    def dependencies
      deps = super
      deps.each_with_index do |dependency, index|
        relaxed = WidenRecordingStudioRequirement.relax(dependency)
        deps[index] = relaxed unless relaxed.equal?(dependency)
      end
      deps
    end
  end

  def self.install!
    return if Gem::Specification < SpecificationPatch

    Gem::Specification.prepend(SpecificationPatch)
  end

  def self.relax(dependency)
    return dependency unless dependency.name == NAME
    return dependency if dependency.requirement.satisfied_by?(VERSION)

    Gem::Dependency.new(NAME, REQUIREMENT, dependency.type)
  end
end

WidenRecordingStudioRequirement.install!
