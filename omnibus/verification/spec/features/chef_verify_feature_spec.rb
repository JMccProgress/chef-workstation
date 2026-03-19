#
# Copyright:: Copyright (c) 2014-2021 Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# BDD-style feature specifications for Chef Workstation verification.
#
# These tests describe observed behaviors from the perspective of a Chef
# Workstation user. Each context block maps to a user story and each
# example expresses a concrete, observable outcome written in
# Given-When-Then style to serve as living documentation of intended
# behavior.

require_relative "../spec_helper"
require_relative "../../verify"

module Gem
  class << self
    alias :real_ruby :ruby unless method_defined?(:real_ruby)
  end
end

RSpec.describe "Chef Workstation verification" do

  let(:verifier)        { ChefWorkstation::Command::Verify.new }
  let(:captured_stdout) { StringIO.new }
  let(:captured_stderr) { StringIO.new }
  let(:ruby_path)       { File.join(fixtures_path, "eg_omnibus_dir/valid/embedded/bin/ruby") }

  def output
    captured_stdout.string
  end

  before do
    allow(Gem).to receive(:ruby).and_return(ruby_path)
    allow(verifier).to receive(:stdout).and_return(captured_stdout)
    allow(verifier).to receive(:stderr).and_return(captured_stderr)
  end

  # Helpers: build lightweight components backed by the fixture omnibus tree.

  def healthy_component(name, app_dir)
    ChefWorkstation::ComponentTest.new(name).tap do |c|
      c.base_dir = app_dir
      c.smoke_test { sh("exit 0") }
    end
  end

  def broken_component(name, app_dir)
    ChefWorkstation::ComponentTest.new(name).tap do |c|
      c.base_dir = app_dir
      c.smoke_test { sh("exit 1") }
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Verifying a healthy Chef Workstation installation
  #
  # As a Chef Workstation user
  # I want to run `chef verify` and receive confirmation that my tools work
  # So that I can be confident in my development environment before I start work
  # ---------------------------------------------------------------------------

  context "As a user verifying a healthy installation" do
    before do
      allow(verifier).to receive(:components).and_return([
        healthy_component("berkshelf",    "embedded/apps/berkshelf"),
        healthy_component("test-kitchen", "embedded/apps/test-kitchen"),
      ])
    end

    # Given: all components have working smoke tests
    # When:  I run `chef verify` with no arguments
    # Then:  the command exits 0
    it "exits successfully when all components pass their smoke tests" do
      expect(verifier.run([])).to eq(0)
    end

    # Then: I see a clear success message for every component
    it "reports success for each verified component" do
      verifier.run([])
      expect(output).to include("Verification of component 'berkshelf' succeeded.")
      expect(output).to include("Verification of component 'test-kitchen' succeeded.")
    end

    # Then: I see a results summary with a clear visual separator
    it "shows a visual separator above the results summary" do
      verifier.run([])
      expect(output).to include("---------------------------------------------")
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Diagnosing a broken Chef Workstation installation
  #
  # As a Chef Workstation user whose installation has a broken component
  # I want `chef verify` to identify exactly what is failing
  # So that I know what to fix or reinstall
  # ---------------------------------------------------------------------------

  context "As a user diagnosing a broken installation" do
    before do
      allow(verifier).to receive(:components).and_return([
        healthy_component("berkshelf",  "embedded/apps/berkshelf"),
        broken_component("chef-client", "embedded/apps/chef"),
      ])
    end

    # Given: one component's smoke test fails
    # When:  I run `chef verify`
    # Then:  the exit code signals failure to any calling process
    it "exits with a non-zero status code when any component fails" do
      expect(verifier.run([])).to eq(1)
    end

    # Then: I can see exactly which component is broken
    it "clearly identifies the failing component by name" do
      verifier.run([])
      expect(output).to include("Verification of component 'chef-client' failed.")
    end

    # Then: I can still see which components remain healthy
    it "reports passing components alongside the failure" do
      verifier.run([])
      expect(output).to include("Verification of component 'berkshelf' succeeded.")
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Targeted component verification for quick feedback
  #
  # As a Chef Workstation user who suspects one specific tool is broken
  # I want to verify just that tool
  # So that I get fast feedback without running the full suite
  # ---------------------------------------------------------------------------

  context "As a user running verification for a single component" do
    before do
      allow(verifier).to receive(:components).and_return([
        healthy_component("berkshelf",    "embedded/apps/berkshelf"),
        healthy_component("test-kitchen", "embedded/apps/test-kitchen"),
      ])
    end

    # Given: multiple components are registered
    # When:  I run `chef verify berkshelf`
    # Then:  only berkshelf is exercised
    it "only verifies the named component" do
      verifier.run(["berkshelf"])
      expect(output).to     include("Verification of component 'berkshelf' succeeded.")
      expect(output).not_to include("Verification of component 'test-kitchen'")
    end

    # Then: the exit code correctly reflects just that component
    it "exits successfully when the targeted component passes" do
      expect(verifier.run(["berkshelf"])).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Verbose output for debugging component failures
  #
  # As a Chef Workstation developer debugging a failing component
  # I want to see the full output from each component's test script
  # So that I can pinpoint the root cause of the problem
  # ---------------------------------------------------------------------------

  context "As a developer using verbose mode to debug a component" do
    let(:unit_test_block) do
      lambda { |_self| sh("#{Gem.real_ruby} verify_me", env: { "RUBYOPT" => "" }) }
    end

    before do
      component = ChefWorkstation::ComponentTest.new("berkshelf").tap do |c|
        c.base_dir = "embedded/apps/berkshelf"
        c.unit_test(&unit_test_block)
        c.smoke_test { sh("exit 0") }
      end
      allow(verifier).to receive(:components).and_return([component])
    end

    # Given: a component with unit tests
    # When:  I run `chef verify --unit --verbose`
    # Then:  I see the internal output from the component's test script
    it "displays component test output when --verbose is used" do
      verifier.run(%w{--unit --verbose})
      expect(output).to include("you are good to go...")
    end

    # When:  I run without --verbose
    # Then:  the internal component output is suppressed
    it "suppresses component test output when --verbose is omitted" do
      verifier.run(%w{--unit})
      expect(output).not_to include("you are good to go...")
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Running deeper test levels during a build
  #
  # As a Chef Workstation developer validating a build
  # I want to run unit and integration tests in addition to smoke tests
  # So that I can catch deeper issues before shipping a release
  # ---------------------------------------------------------------------------

  context "As a developer running unit and integration tests during a build" do
    let(:unit_test_block) do
      lambda { |_self| sh("#{Gem.real_ruby} verify_me", env: { "RUBYOPT" => "" }) }
    end

    let(:integration_test_block) do
      lambda { |_self| sh("#{Gem.real_ruby} integration_test", env: { "RUBYOPT" => "" }) }
    end

    before do
      component = ChefWorkstation::ComponentTest.new("berkshelf").tap do |c|
        c.base_dir = "embedded/apps/berkshelf"
        c.unit_test(&unit_test_block)
        c.integration_test(&integration_test_block)
        c.smoke_test { sh("exit 0") }
      end
      allow(verifier).to receive(:components).and_return([component])
    end

    # Given: a component with unit tests defined
    # When:  I pass --unit --verbose
    # Then:  the unit test script is executed and its output is visible
    it "runs unit tests when the --unit flag is passed" do
      verifier.run(%w{--unit --verbose})
      expect(output).to include("you are good to go...")
    end

    # Given: a component with integration tests defined
    # When:  I pass --integration --verbose
    # Then:  the integration test script is executed
    it "runs integration tests when the --integration flag is passed" do
      verifier.run(%w{--integration --verbose})
      expect(output).to include("integration tests OK")
    end

    # When:  both flags are passed and everything passes
    # Then:  the command succeeds
    it "exits successfully when all test levels pass" do
      expect(verifier.run(%w{--unit --integration})).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Clear errors for incomplete installations
  #
  # As a Chef Workstation user with an incomplete or corrupt installation
  # I want an informative error message when a component cannot be located
  # So that I understand what I need to fix
  # ---------------------------------------------------------------------------

  context "As a user with an incomplete installation" do
    # Given: a component is registered but its files do not exist on disk
    # When:  chef verify attempts to validate that component
    # Then:  a MissingComponentError is raised with the component name in the message
    it "raises an informative error that names the missing component" do
      component = ChefWorkstation::ComponentTest.new("missing-tool").tap do |c|
        c.base_dir = "nonexistent/path"
      end
      allow(verifier).to receive(:components).and_return([component])

      expect { verifier.validate_components! }.to raise_error(
        ChefWorkstation::MissingComponentError,
        /missing-tool/
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Reliable integration with CI/CD pipelines
  #
  # As a CI/CD pipeline running Chef Workstation build verification
  # I want consistent exit codes and machine-readable status lines in the output
  # So that the pipeline can automatically detect and react to failures
  # ---------------------------------------------------------------------------

  context "As a CI/CD pipeline consuming verification results" do
    # Given: all registered components are healthy
    # When:  the verification suite runs
    # Then:  the pipeline receives exit code 0 (success)
    it "returns exit code 0 when all components pass" do
      allow(verifier).to receive(:components).and_return([
        healthy_component("berkshelf",    "embedded/apps/berkshelf"),
        healthy_component("test-kitchen", "embedded/apps/test-kitchen"),
      ])
      expect(verifier.run([])).to eq(0)
    end

    # Given: one component is broken
    # When:  the verification suite runs
    # Then:  the pipeline receives exit code 1 (failure)
    it "returns exit code 1 when any component fails" do
      allow(verifier).to receive(:components).and_return([
        healthy_component("berkshelf", "embedded/apps/berkshelf"),
        broken_component("bad-tool",   "embedded/apps/chef"),
      ])
      expect(verifier.run([])).to eq(1)
    end

    # Then: the output contains consistently formatted status lines
    #       that a log parser or shell script can grep for reliably
    it "produces consistently formatted, parseable component status lines" do
      allow(verifier).to receive(:components).and_return([
        healthy_component("myapp", "embedded/apps/berkshelf"),
      ])
      verifier.run([])
      expect(output).to match(/Verification of component '.*' (succeeded|failed)\./)
    end

    # Then: every component status line follows the same naming convention,
    #       allowing downstream tools to extract component names unambiguously
    it "includes the component name in the status line" do
      allow(verifier).to receive(:components).and_return([
        healthy_component("myapp", "embedded/apps/berkshelf"),
      ])
      verifier.run([])
      expect(output).to include("Verification of component 'myapp' succeeded.")
    end
  end
end
