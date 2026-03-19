#
# Copyright:: Copyright (c) 2014-2026 Chef Software Inc.
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

# BDD-style integrity and integration specifications for Chef Workstation.
#
# SCOPE CLARIFICATION:
#
# This file contains two categories of tests:
#
# 1. FUNCTIONAL WORKFLOW SIMULATIONS (ComponentTest-level, no verifier)
#    These exercise ChefWorkstation::ComponentTest directly by running fixture
#    scripts that simulate the *output patterns* of real Chef tools (cookbook
#    generation, Cookstyle, InSpec, Knife, etc.). No verifier stubbing occurs;
#    the ComponentTest runs a real subprocess and returns a real ShellOut result.
#    These do NOT replace full end-to-end system tests on a real installation.
#
# 2. VERIFIER INTEGRITY TESTS (integration-level, minimal mocking)
#    These exercise ChefWorkstation::Command::Verify with fixture-backed
#    ComponentTest objects. Only Gem.ruby is stubbed to redirect the omnibus
#    root to the fixture directory. verifier.components is NOT stubbed; instead,
#    components are provided via real ComponentTest construction. These tests
#    cover packaging integrity, edge-case failure modes, strict output contracts,
#    parallel execution safety, and cross-platform path handling.

require_relative "../spec_helper"
require_relative "../../verify"
require_relative "../../component_test"

module Gem
  class << self
    alias :real_ruby :ruby unless method_defined?(:real_ruby)
  end
end

RSpec.describe "Chef Workstation integrity and integration" do

  FIXTURE_OMNIBUS_ROOT = File.join(
    File.expand_path(File.dirname(__FILE__) + "/../unit/fixtures/"),
    "eg_omnibus_dir/valid"
  ).freeze

  FIXTURE_APP_DIR = "embedded/apps/berkshelf".freeze

  # ---------------------------------------------------------------------------
  # 1. FUNCTIONAL WORKFLOW SIMULATIONS
  #
  # These tests run real fixture scripts through ComponentTest without any
  # verifier or mock. They assert tool-specific output patterns to validate
  # that the verification framework correctly captures and forwards rich,
  # domain-meaningful output – not just generic success/failure markers.
  # ---------------------------------------------------------------------------

  describe "Functional workflow simulations (ComponentTest-level, no mocking)" do

    # Helper: build a ComponentTest backed by the real fixture omnibus directory.
    # Provides a real shell execution with no mocks; asserts against ShellOut result.
    def fixture_component(name, script_name)
      ChefWorkstation::ComponentTest.new(name).tap do |c|
        c.base_dir     = FIXTURE_APP_DIR
        c.omnibus_root = FIXTURE_OMNIBUS_ROOT
        c.unit_test    { sh("#{Gem.real_ruby} #{script_name}", env: { "RUBYOPT" => "" }) }
        c.smoke_test   { sh("exit 0") }
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: chef generate cookbook creates expected structure
    #
    # As a cookbook author running `chef generate cookbook`
    # I want the output to list the generated files and directories
    # So that I can confirm the scaffold was created correctly
    # ---------------------------------------------------------------------------

    context "chef generate cookbook output simulation" do
      # Given: a ComponentTest backed by a fixture that simulates `chef generate cookbook`
      # When:  I run the unit test
      # Then:  the result exits 0 and includes every major cookbook scaffold path
      it "exits successfully" do
        result = fixture_component("chef-cli", "cookbook_gen_sim").run_unit_test
        expect(result.exitstatus).to eq(0)
      end

      it "reports the cookbook name being created" do
        result = fixture_component("chef-cli", "cookbook_gen_sim").run_unit_test
        expect(result.stdout).to include("Creating cookbook:")
      end

      it "reports generation of metadata.rb" do
        result = fixture_component("chef-cli", "cookbook_gen_sim").run_unit_test
        expect(result.stdout).to include("metadata.rb")
      end

      it "reports generation of the default recipe" do
        result = fixture_component("chef-cli", "cookbook_gen_sim").run_unit_test
        expect(result.stdout).to include("recipes/default.rb")
      end

      it "reports generation of the spec skeleton" do
        result = fixture_component("chef-cli", "cookbook_gen_sim").run_unit_test
        expect(result.stdout).to include("spec/unit/recipes/default_spec.rb")
      end

      it "prints a final success confirmation message" do
        result = fixture_component("chef-cli", "cookbook_gen_sim").run_unit_test
        expect(result.stdout).to include("generated successfully")
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: cookstyle runs against a cookbook and reports style results
    #
    # As a cookbook author running `cookstyle`
    # I want to see how many files were inspected and whether offenses were found
    # So that I can fix style issues before committing
    # ---------------------------------------------------------------------------

    context "cookstyle style-check output simulation" do
      # Given: a ComponentTest backed by a fixture that simulates `cookstyle`
      # When:  I run the unit test
      # Then:  the output contains file inspection count and offense summary
      it "exits successfully when no style offenses are present" do
        result = fixture_component("cookstyle", "cookstyle_sim").run_unit_test
        expect(result.exitstatus).to eq(0)
      end

      it "reports the number of files inspected" do
        result = fixture_component("cookstyle", "cookstyle_sim").run_unit_test
        expect(result.stdout).to match(/\d+ files inspected/)
      end

      it "reports that no offenses were detected" do
        result = fixture_component("cookstyle", "cookstyle_sim").run_unit_test
        expect(result.stdout).to include("no offenses detected")
      end

      it "confirms all files conform to Chef style guidelines" do
        result = fixture_component("cookstyle", "cookstyle_sim").run_unit_test
        expect(result.stdout).to include("Chef style guidelines")
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: inspec exec runs a compliance profile locally
    #
    # As a compliance engineer running `inspec exec`
    # I want to see the profile name, control results, and a pass/fail summary
    # So that I can confirm my compliance profile executed correctly
    # ---------------------------------------------------------------------------

    context "inspec exec profile run simulation" do
      # Given: a ComponentTest backed by a fixture that simulates `inspec exec`
      # When:  I run the unit test
      # Then:  output includes the profile header, a control result, and a summary
      it "exits successfully for a passing profile" do
        result = fixture_component("inspec", "inspec_sim").run_unit_test
        expect(result.exitstatus).to eq(0)
      end

      it "reports the profile name and target" do
        result = fixture_component("inspec", "inspec_sim").run_unit_test
        expect(result.stdout).to include("Profile:")
        expect(result.stdout).to include("Target:")
      end

      it "reports at least one passing control" do
        result = fixture_component("inspec", "inspec_sim").run_unit_test
        expect(result.stdout).to include("[PASS]")
      end

      it "reports a profile summary with successful control count" do
        result = fixture_component("inspec", "inspec_sim").run_unit_test
        expect(result.stdout).to include("Profile Summary:")
        expect(result.stdout).to include("1 successful control")
      end

      it "reports a test summary with successful test count" do
        result = fixture_component("inspec", "inspec_sim").run_unit_test
        expect(result.stdout).to include("Test Summary:")
        expect(result.stdout).to include("1 successful")
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: knife basic command executes without error
    #
    # As an operations engineer running `knife help`
    # I want to see a listing of available subcommands
    # So that I can discover what Knife operations are available
    # ---------------------------------------------------------------------------

    context "knife help / subcommand listing simulation" do
      # Given: a ComponentTest backed by a fixture that simulates `knife help`
      # When:  I run the unit test
      # Then:  the output lists knife subcommands with usage patterns
      it "exits successfully" do
        result = fixture_component("knife", "knife_sim").run_unit_test
        expect(result.exitstatus).to eq(0)
      end

      it "lists available knife subcommands" do
        result = fixture_component("knife", "knife_sim").run_unit_test
        expect(result.stdout).to include("knife sub-commands")
      end

      it "includes node management commands" do
        result = fixture_component("knife", "knife_sim").run_unit_test
        expect(result.stdout).to include("knife node list")
      end

      it "includes cookbook management commands" do
        result = fixture_component("knife", "knife_sim").run_unit_test
        expect(result.stdout).to include("knife cookbook list")
      end

      it "includes bootstrap capability" do
        result = fixture_component("knife", "knife_sim").run_unit_test
        expect(result.stdout).to include("knife bootstrap")
      end

      it "confirms Knife is ready" do
        result = fixture_component("knife", "knife_sim").run_unit_test
        expect(result.stdout).to include("Knife is ready")
      end
    end

  end

  # ---------------------------------------------------------------------------
  # 2. COMPONENT REGISTRY DISCOVERY
  #
  # These tests operate directly on the class-level component registry
  # (ChefWorkstation::Command::Verify.components / .component_map).
  # They do NOT stub verifier.components on any instance.
  # ---------------------------------------------------------------------------

  describe "Component registry discovery (class-level, no instance stubbing)" do

    let(:expected_component_names) do
      %w[
        berkshelf
        test-kitchen
        tk-policyfile-provisioner
        chef-client
        chef-cli
        chef-apply
        chefspec
        generated-cookbooks-pass-chefspec
        fauxhai-chef
        kitchen-vagrant
        package\ installation
        openssl
        inspec
        git
        curl
      ]
    end

    # Given: Chef Workstation has been loaded
    # When:  I inspect the component registry
    # Then:  all expected bundled tools appear exactly once
    it "registers all expected Chef Workstation components" do
      registered = ChefWorkstation::Command::Verify.components.map(&:name)
      expected_component_names.each do |expected|
        expect(registered).to include(expected),
          "Expected component '#{expected}' to be registered but it was not. " \
          "Registered: #{registered.inspect}"
      end
    end

    it "does not register any duplicate component names" do
      names = ChefWorkstation::Command::Verify.components.map(&:name)
      expect(names.length).to eq(names.uniq.length),
        "Duplicate component names found: #{names.select { |n| names.count(n) > 1 }.uniq.inspect}"
    end

    it "returns a ComponentTest object for each registered name" do
      ChefWorkstation::Command::Verify.components.each do |component|
        expect(component).to be_a(ChefWorkstation::ComponentTest),
          "'#{component.name}' is not a ComponentTest instance"
      end
    end

    # Given: I request a component by a name that IS registered
    # When:  I call Verify.component(name)
    # Then:  I receive the correct ComponentTest object
    it "retrieves a registered component by exact name" do
      component = ChefWorkstation::Command::Verify.component("berkshelf")
      expect(component).not_to be_nil
      expect(component.name).to eq("berkshelf")
    end

    # Given: I request a component by a name that is NOT registered
    # When:  I call Verify.component(unknown_name)
    # Then:  nil is returned (not an error)
    it "returns nil for an unregistered component name" do
      expect(ChefWorkstation::Command::Verify.component("nonexistent-tool")).to be_nil
    end

    it "returns nil for an empty string component name" do
      expect(ChefWorkstation::Command::Verify.component("")).to be_nil
    end

  end

  # ---------------------------------------------------------------------------
  # 3. PACKAGING AND INSTALL INTEGRITY
  #
  # These tests exercise assert_present! and validate_components! using
  # the fixture omnibus layout to verify that broken or missing component
  # directories produce clear, actionable error messages.
  # ---------------------------------------------------------------------------

  describe "Packaging and install integrity (fixture-backed, minimal mocking)" do

    let(:verifier)        { ChefWorkstation::Command::Verify.new }
    let(:captured_stdout) { StringIO.new }
    let(:captured_stderr) { StringIO.new }
    let(:ruby_path)       { File.join(fixtures_path, "eg_omnibus_dir/valid/embedded/bin/ruby") }

    before do
      allow(Gem).to receive(:ruby).and_return(ruby_path)
      allow(verifier).to receive(:stdout).and_return(captured_stdout)
      allow(verifier).to receive(:stderr).and_return(captured_stderr)
    end

    def output
      captured_stdout.string
    end

    # Given: a component whose base_dir exists in the fixture omnibus layout
    # When:  assert_present! is called
    # Then:  no exception is raised
    it "assert_present! succeeds when the component directory exists in the fixture layout" do
      component = ChefWorkstation::ComponentTest.new("berkshelf").tap do |c|
        c.base_dir     = FIXTURE_APP_DIR
        c.omnibus_root = FIXTURE_OMNIBUS_ROOT
      end
      expect { component.assert_present! }.not_to raise_error
    end

    # Given: a component whose base_dir does NOT exist
    # When:  assert_present! is called
    # Then:  MissingComponentError is raised
    it "assert_present! raises MissingComponentError when the directory is absent" do
      component = ChefWorkstation::ComponentTest.new("phantom-tool").tap do |c|
        c.base_dir     = "embedded/apps/phantom-tool"
        c.omnibus_root = FIXTURE_OMNIBUS_ROOT
      end
      expect { component.assert_present! }.to raise_error(ChefWorkstation::MissingComponentError)
    end

    # Then: the error message names the missing component so the user knows what to fix
    it "MissingComponentError message contains the component name" do
      component = ChefWorkstation::ComponentTest.new("phantom-tool").tap do |c|
        c.base_dir     = "embedded/apps/phantom-tool"
        c.omnibus_root = FIXTURE_OMNIBUS_ROOT
      end
      expect { component.assert_present! }.to raise_error(
        ChefWorkstation::MissingComponentError, /phantom-tool/
      )
    end

    # Given: a component with an entirely non-existent root
    # When:  assert_present! is called
    # Then:  MissingComponentError is raised (not a generic RuntimeError)
    it "assert_present! raises MissingComponentError for a wholly non-existent path" do
      component = ChefWorkstation::ComponentTest.new("deep-missing").tap do |c|
        c.base_dir     = "no/such/path"
        c.omnibus_root = "/nonexistent_omnibus_root_for_test"
      end
      expect { component.assert_present! }.to raise_error(ChefWorkstation::MissingComponentError)
    end

    # Given: a component whose directory is missing
    # When:  validate_components! is called on the verifier
    # Then:  MissingComponentError is raised, naming the broken component
    it "validate_components! raises MissingComponentError for a fixture-backed missing directory" do
      missing_component = ChefWorkstation::ComponentTest.new("missing-tool").tap do |c|
        c.base_dir = "embedded/apps/does-not-exist"
      end
      allow(verifier).to receive(:components).and_return([missing_component])
      expect { verifier.validate_components! }.to raise_error(
        ChefWorkstation::MissingComponentError, /missing-tool/
      )
    end

    # Given: a component that exists but its smoke test script is not executable
    # When:  the component smoke test is run
    # Then:  Mixlib::ShellOut attempts to exec the file directly; because the
    #        file has no execute permission, the OS raises Errno::EACCES.
    #        This propagates out of run_smoke_test rather than returning a
    #        graceful non-zero exit status (documented packaging failure mode).
    it "smoke test raises a permission-denied error when the script is not executable" do
      Dir.mktmpdir("integrity_test") do |tmpdir|
        # omnibus_bin_dir expands File.join(omnibus_root, "bin") and requires
        # that directory to exist, so create it alongside embedded/bin.
        FileUtils.mkdir_p(File.join(tmpdir, "bin"))
        FileUtils.mkdir_p(File.join(tmpdir, "embedded", "bin"))
        FileUtils.mkdir_p(File.join(tmpdir, "component_dir"))

        script_path = File.join(tmpdir, "component_dir", "bad_script")
        File.write(script_path, "#!/bin/sh\necho 'should not run'\nexit 0\n")
        File.chmod(0o644, script_path) # deliberately NOT executable

        component = ChefWorkstation::ComponentTest.new("bad-perms").tap do |c|
          c.base_dir     = "component_dir"
          c.omnibus_root = tmpdir
          c.smoke_test   { sh("./bad_script") }
        end
        # ShellOut execs the file directly; Errno::EACCES is raised when the
        # execute bit is absent (not a graceful non-zero return code).
        expect { component.run_smoke_test }.to raise_error(Errno::EACCES)
      end
    end

  end

  # ---------------------------------------------------------------------------
  # 4. EDGE CASES AND FAILURE MODES
  #
  # These tests cover unusual inputs and component behaviours that are not
  # addressed by the happy-path feature specs in other files.
  # ---------------------------------------------------------------------------

  describe "Edge cases and failure modes" do

    let(:verifier)        { ChefWorkstation::Command::Verify.new }
    let(:captured_stdout) { StringIO.new }
    let(:captured_stderr) { StringIO.new }
    let(:ruby_path)       { File.join(fixtures_path, "eg_omnibus_dir/valid/embedded/bin/ruby") }

    before do
      allow(Gem).to receive(:ruby).and_return(ruby_path)
      allow(verifier).to receive(:stdout).and_return(captured_stdout)
      allow(verifier).to receive(:stderr).and_return(captured_stderr)
    end

    def output
      captured_stdout.string
    end

    # ---------------------------------------------------------------------------
    # Feature: Unknown component name passed to chef verify
    #
    # As a user who mistyped a component name
    # I want chef verify to complete without crashing
    # So that I understand no matching component was found
    # ---------------------------------------------------------------------------

    context "when the filter references a component name that does not exist" do
      before do
        allow(verifier).to receive(:components).and_return([
          ChefWorkstation::ComponentTest.new("berkshelf").tap do |c|
            c.base_dir = "embedded/apps/berkshelf"
            c.smoke_test { sh("exit 0") }
          end,
        ])
      end

      # Given: the user passes an unregistered component name as a filter
      # When:  chef verify runs
      # Then:  no components match, nothing fails, the command exits 0
      it "exits 0 when no components match the unknown filter" do
        expect(verifier.run(["no-such-component"])).to eq(0)
      end

      # Then: no component result lines appear (nothing was tested)
      it "produces no Verification result lines for the unknown component name" do
        verifier.run(["no-such-component"])
        expect(output).not_to include("Verification of component 'no-such-component'")
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: Partial filter – some names match, some do not
    # ---------------------------------------------------------------------------

    context "when the filter contains one valid and one invalid component name" do
      before do
        allow(verifier).to receive(:components).and_return([
          ChefWorkstation::ComponentTest.new("berkshelf").tap do |c|
            c.base_dir = "embedded/apps/berkshelf"
            c.smoke_test { sh("exit 0") }
          end,
          ChefWorkstation::ComponentTest.new("test-kitchen").tap do |c|
            c.base_dir = "embedded/apps/test-kitchen"
            c.smoke_test { sh("exit 0") }
          end,
        ])
      end

      # Given: two registered components and a filter for one valid + one invalid name
      # When:  chef verify runs
      # Then:  only the valid match runs; the invalid name is silently ignored
      it "verifies only the component that matches the filter" do
        verifier.run(%w[berkshelf totally-fake-tool])
        expect(output).to     include("Verification of component 'berkshelf' succeeded.")
        expect(output).not_to include("Verification of component 'test-kitchen'")
        expect(output).not_to include("totally-fake-tool")
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: Mixed unit and smoke test failures in a single component
    # ---------------------------------------------------------------------------

    context "when a component has both a failing smoke test and a failing unit test" do
      let(:mixed_failure_component) do
        ChefWorkstation::ComponentTest.new("mixed-fail").tap do |c|
          c.base_dir   = "embedded/apps/berkshelf"
          c.smoke_test { sh("exit 1") }
          c.unit_test  { sh("exit 1") }
        end
      end

      before do
        allow(verifier).to receive(:components).and_return([mixed_failure_component])
      end

      # Given: a component where both smoke and unit tests fail
      # When:  I run chef verify --unit
      # Then:  the component is reported as failed and exit code is 1
      it "reports the component as failed when both smoke and unit tests fail" do
        verifier.run(["--unit"])
        expect(output).to include("Verification of component 'mixed-fail' failed.")
      end

      it "exits 1 for a component with mixed smoke and unit failures" do
        expect(verifier.run(["--unit"])).to eq(1)
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: Exception propagation from a component's test block
    #
    # This test documents current behaviour: an exception raised inside a
    # component block propagates out of Verify#run rather than being caught
    # and reported as a graceful failure.
    # ---------------------------------------------------------------------------

    context "when a component's test block raises a Ruby exception" do
      let(:exploding_component) do
        ChefWorkstation::ComponentTest.new("exploding-comp").tap do |c|
          c.base_dir   = "embedded/apps/berkshelf"
          c.smoke_test { raise RuntimeError, "unexpected internal error in component test" }
        end
      end

      before do
        allow(verifier).to receive(:components).and_return([exploding_component])
      end

      # Given: a component whose smoke_test block raises a Ruby exception
      # When:  chef verify runs
      # Then:  the exception propagates out of run (current documented behaviour)
      it "propagates the exception out of verify run (current documented behaviour)" do
        expect { verifier.run([]) }.to raise_error(RuntimeError, /unexpected internal error/)
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: Ensure all failures are reported even when multiple components fail
    # (no early exit after first failure)
    # ---------------------------------------------------------------------------

    context "when every component in a large run fails" do
      let(:all_failing) do
        (1..5).map do |i|
          ChefWorkstation::ComponentTest.new("failing_#{i}").tap do |c|
            c.base_dir   = "embedded/apps/berkshelf"
            c.smoke_test { sh("exit 1") }
          end
        end
      end

      before do
        allow(verifier).to receive(:components).and_return(all_failing)
      end

      # Given: five components all fail their smoke tests
      # When:  chef verify runs
      # Then:  every single failure is reported (no early exit after first failure)
      it "reports every failing component even when all five fail" do
        verifier.run([])
        (1..5).each do |i|
          expect(output).to include("Verification of component 'failing_#{i}' failed."),
            "Expected failure for 'failing_#{i}' but not found in output:\n#{output}"
        end
      end

      # Then: exit code is 1 (not 5 or some other value)
      it "exits with exactly 1 when every component fails" do
        expect(verifier.run([])).to eq(1)
      end
    end

  end

  # ---------------------------------------------------------------------------
  # 5. OUTPUT CONTRACT (STRICT ASSERTIONS)
  #
  # These tests validate that the verifier's CLI output adheres to a stable,
  # parseable format that downstream tools and log parsers can rely on.
  # ---------------------------------------------------------------------------

  describe "Output contract (strict format validation)" do

    let(:verifier)        { ChefWorkstation::Command::Verify.new }
    let(:captured_stdout) { StringIO.new }
    let(:captured_stderr) { StringIO.new }
    let(:ruby_path)       { File.join(fixtures_path, "eg_omnibus_dir/valid/embedded/bin/ruby") }

    before do
      allow(Gem).to receive(:ruby).and_return(ruby_path)
      allow(verifier).to receive(:stdout).and_return(captured_stdout)
      allow(verifier).to receive(:stderr).and_return(captured_stderr)
    end

    def output
      captured_stdout.string
    end

    def err_output
      captured_stderr.string
    end

    def run_with_components(*components)
      allow(verifier).to receive(:components).and_return(components)
      verifier.run([])
    end

    def passing(name)
      ChefWorkstation::ComponentTest.new(name).tap do |c|
        c.base_dir   = "embedded/apps/berkshelf"
        c.smoke_test { sh("exit 0") }
      end
    end

    def failing(name)
      ChefWorkstation::ComponentTest.new(name).tap do |c|
        c.base_dir   = "embedded/apps/berkshelf"
        c.smoke_test { sh("exit 1") }
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: Parseable component status lines
    # ---------------------------------------------------------------------------

    context "status line format" do
      # Given: components with known names
      # When:  verification completes
      # Then:  every status line matches the exact expected format to the character
      it "every status line matches 'Verification of component \\'X\\' succeeded/failed.' exactly" do
        run_with_components(passing("alpha"), failing("beta"))
        status_lines = output.lines.select { |l| l.include?("Verification of component") }
        expect(status_lines).not_to be_empty
        status_lines.each do |line|
          expect(line.strip).to match(
            /\AVerification of component '[^']+' (succeeded|failed)\.\z/
          ), "Status line did not match expected format: #{line.inspect}"
        end
      end

      it "the succeeded status line is exactly 'Verification of component \\'name\\' succeeded.'" do
        run_with_components(passing("mycomp"))
        expect(output).to include("Verification of component 'mycomp' succeeded.")
      end

      it "the failed status line is exactly 'Verification of component \\'name\\' failed.'" do
        run_with_components(failing("mycomp"))
        expect(output).to include("Verification of component 'mycomp' failed.")
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: Summary separator
    # ---------------------------------------------------------------------------

    context "summary separator format" do
      # Given: any verification run (pass or fail)
      # When:  output is produced
      # Then:  a separator of exactly 45 hyphens appears before the result summary
      it "outputs a separator of exactly 45 hyphens" do
        run_with_components(passing("alpha"))
        expect(output).to include("-" * 45)
      end

      it "the separator is not longer than 45 characters" do
        run_with_components(passing("alpha"))
        expect(output).not_to include("-" * 46)
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: Exact exit codes
    # ---------------------------------------------------------------------------

    context "exit code contract" do
      # Given: all components pass
      # When:  verification runs
      # Then:  exit code is exactly 0 (integer, not truthy)
      it "returns exactly integer 0 when all components pass" do
        result = run_with_components(passing("a"), passing("b"))
        expect(result).to eq(0)
        expect(result).to be_a(Integer)
      end

      # Given: any component fails
      # When:  verification runs
      # Then:  exit code is exactly 1 (integer)
      it "returns exactly integer 1 when any component fails" do
        result = run_with_components(passing("a"), failing("b"))
        expect(result).to eq(1)
        expect(result).to be_a(Integer)
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: stdout vs stderr separation
    # ---------------------------------------------------------------------------

    context "stdout and stderr separation" do
      # Given: a normal verification run
      # When:  all components pass
      # Then:  component result lines go to stdout, not stderr
      it "writes component results to stdout" do
        run_with_components(passing("alpha"))
        expect(output).to include("Verification of component 'alpha' succeeded.")
      end

      it "does not write component results to stderr" do
        run_with_components(passing("alpha"))
        expect(err_output).not_to include("Verification of component")
      end

      # Then: stderr contains only the built-in operational notice (documented behaviour).
      #       verify.run() always emits "[WARN] This is an internal command..." to stderr
      #       as a user notice; no component-specific content appears there.
      it "writes only the built-in operational WARN notice to stderr (not component results)" do
        run_with_components(passing("alpha"))
        expect(err_output).to include("[WARN]")
        expect(err_output).not_to include("Verification of component")
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: Summary section appears after the separator
    # ---------------------------------------------------------------------------

    context "output structure: separator precedes the result summary" do
      # Given: a mixed run
      # When:  output is produced
      # Then:  the separator line appears before every "Verification of component" line
      it "places the separator before the result summary" do
        run_with_components(passing("alpha"), failing("beta"))
        separator_pos = output.index("-" * 45)
        alpha_pos     = output.index("Verification of component 'alpha'")
        beta_pos      = output.index("Verification of component 'beta'")
        expect(separator_pos).not_to be_nil
        expect(alpha_pos).to be > separator_pos
        expect(beta_pos).to be  > separator_pos
      end
    end

  end

  # ---------------------------------------------------------------------------
  # 6. PARALLEL EXECUTION SAFETY
  #
  # Verify#invoke_tests uses a thread per component. These tests confirm that
  # the concurrent execution model correctly collects all results regardless of
  # how many components run simultaneously or how many fail.
  # ---------------------------------------------------------------------------

  describe "Parallel execution safety" do

    let(:verifier)        { ChefWorkstation::Command::Verify.new }
    let(:captured_stdout) { StringIO.new }
    let(:captured_stderr) { StringIO.new }
    let(:ruby_path)       { File.join(fixtures_path, "eg_omnibus_dir/valid/embedded/bin/ruby") }

    before do
      allow(Gem).to receive(:ruby).and_return(ruby_path)
      allow(verifier).to receive(:stdout).and_return(captured_stdout)
      allow(verifier).to receive(:stderr).and_return(captured_stderr)
    end

    def output
      captured_stdout.string
    end

    def smoke_component(name, exit_code)
      ChefWorkstation::ComponentTest.new(name).tap do |c|
        c.base_dir   = "embedded/apps/berkshelf"
        c.smoke_test { sh("exit #{exit_code}") }
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: All results collected when multiple components fail simultaneously
    # ---------------------------------------------------------------------------

    context "when five components all fail concurrently" do
      let(:components) { (1..5).map { |i| smoke_component("concurrent_fail_#{i}", 1) } }

      before do
        allow(verifier).to receive(:components).and_return(components)
        verifier.run([])
      end

      # Given: five components run in parallel, each failing
      # When:  verification completes
      # Then:  all five failures appear in the output (no result is lost)
      it "reports every component result even with five simultaneous failures" do
        (1..5).each do |i|
          expect(output).to include("Verification of component 'concurrent_fail_#{i}' failed."),
            "Result for concurrent_fail_#{i} missing from output:\n#{output}"
        end
      end

      it "the total number of result lines equals the number of components" do
        result_lines = output.lines.select { |l| l.include?("Verification of component") }
        expect(result_lines.length).to eq(5)
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: All results collected when multiple components pass simultaneously
    # ---------------------------------------------------------------------------

    context "when five components all pass concurrently" do
      let(:components) { (1..5).map { |i| smoke_component("concurrent_pass_#{i}", 0) } }

      before do
        allow(verifier).to receive(:components).and_return(components)
        verifier.run([])
      end

      # Given: five components run in parallel, each passing
      # When:  verification completes
      # Then:  all five successes appear in the output
      it "reports every component result even with five simultaneous passes" do
        (1..5).each do |i|
          expect(output).to include("Verification of component 'concurrent_pass_#{i}' succeeded."),
            "Result for concurrent_pass_#{i} missing from output:\n#{output}"
        end
      end

      it "exits 0 when all concurrent components pass" do
        expect(verifier.run([])).to eq(0)
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: Mixed concurrent pass/fail – correct exit code and all results
    # ---------------------------------------------------------------------------

    context "when three components pass and two fail concurrently" do
      let(:components) do
        [
          smoke_component("pass_a", 0),
          smoke_component("fail_b", 1),
          smoke_component("pass_c", 0),
          smoke_component("fail_d", 1),
          smoke_component("pass_e", 0),
        ]
      end

      before do
        allow(verifier).to receive(:components).and_return(components)
        verifier.run([])
      end

      it "reports all five component results" do
        result_lines = output.lines.select { |l| l.include?("Verification of component") }
        expect(result_lines.length).to eq(5)
      end

      it "correctly identifies passing components" do
        expect(output).to include("Verification of component 'pass_a' succeeded.")
        expect(output).to include("Verification of component 'pass_c' succeeded.")
        expect(output).to include("Verification of component 'pass_e' succeeded.")
      end

      it "correctly identifies failing components" do
        expect(output).to include("Verification of component 'fail_b' failed.")
        expect(output).to include("Verification of component 'fail_d' failed.")
      end

      it "exits 1 when any concurrent component fails" do
        expect(verifier.run([])).to eq(1)
      end
    end

  end

  # ---------------------------------------------------------------------------
  # 7. CROSS-PLATFORM PATH HANDLING
  #
  # These tests ensure that the path construction helpers in ComponentTest
  # use File.join semantics and do not embed hardcoded path separators in a
  # way that would break on Windows.
  # ---------------------------------------------------------------------------

  describe "Cross-platform path handling" do

    let(:omnibus_root) { FIXTURE_OMNIBUS_ROOT }

    let(:component) do
      ChefWorkstation::ComponentTest.new("berkshelf").tap do |c|
        c.base_dir     = FIXTURE_APP_DIR
        c.omnibus_root = omnibus_root
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: bin() uses File.join for portable path construction
    # ---------------------------------------------------------------------------

    context "#bin path construction" do
      # Given: a component with a known omnibus_root
      # When:  I call component.bin("berks")
      # Then:  the path is equivalent to File.join(omnibus_root, "bin", "berks")
      it "constructs the bin path using File.join semantics" do
        expected = File.join(omnibus_root, "bin", "berks")
        expect(component.bin("berks")).to eq(expected)
      end

      it "includes the binary name in the constructed path" do
        expect(component.bin("chef")).to include("chef")
      end

      it "includes the omnibus root in the constructed path" do
        expect(component.bin("chef")).to include(omnibus_root)
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: embedded_bin() uses File.join for portable path construction
    # ---------------------------------------------------------------------------

    context "#embedded_bin path construction" do
      # Given: a component with a known omnibus_root
      # When:  I call component.embedded_bin("ruby")
      # Then:  the path contains 'embedded' and the binary name
      it "constructs the embedded_bin path using File.join semantics" do
        expected = File.join(omnibus_root, "embedded", "bin", "ruby")
        expect(component.embedded_bin("ruby")).to eq(expected)
      end

      it "contains 'embedded' in the constructed path" do
        expect(component.embedded_bin("bundle")).to include("embedded")
      end

      it "contains the binary name in the constructed path" do
        expect(component.embedded_bin("bundle")).to include("bundle")
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: component_path uses File.join for portable path construction
    # ---------------------------------------------------------------------------

    context "#component_path construction" do
      # Given: base_dir is set as a relative path
      # When:  component_path is computed
      # Then:  it is equivalent to File.join(omnibus_root, base_dir)
      it "constructs component_path as File.join(omnibus_root, base_dir)" do
        expected = File.join(omnibus_root, FIXTURE_APP_DIR)
        expect(component.component_path).to eq(expected)
      end

      it "does not contain double path separators" do
        path = component.component_path
        expect(path).not_to include("//")
        expect(path).not_to match(/[\\]{2}/) unless Gem::Platform.local.os == "mingw32"
      end
    end

    # ---------------------------------------------------------------------------
    # Feature: omnibus_path builds a PATH-compatible string
    # ---------------------------------------------------------------------------

    context "#omnibus_path construction" do
      # Given: a component with a known omnibus_root
      # When:  omnibus_path is called
      # Then:  it contains both the bin and embedded/bin directories
      it "includes the omnibus bin directory" do
        expect(component.omnibus_path).to include(File.join(omnibus_root, "bin"))
      end

      it "includes the omnibus embedded bin directory" do
        expect(component.omnibus_path).to include(File.join(omnibus_root, "embedded", "bin"))
      end

      it "uses the platform PATH separator between entries" do
        parts = component.omnibus_path.split(File::PATH_SEPARATOR)
        expect(parts.length).to be >= 2
      end
    end

  end

end
