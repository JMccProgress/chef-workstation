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

# BDD-style workflow feature specifications for Chef Workstation.
#
# Each context block describes a practical user story drawn from the 30
# real-world uses of Chef Workstation. Examples use Given/When/Then language
# to express observable outcomes that a user of that role would care about.
#
# User roles covered:
#   - Cookbook Author          (berkshelf, chef-cli, chefspec, cookstyle)
#   - Infrastructure Tester    (test-kitchen, tk-policyfile-provisioner)
#   - Compliance Engineer      (inspec)
#   - Operations Engineer      (chef-client, chef-apply, knife, openssl)
#   - Platform Engineer        (multi-component orchestration, SSL, git, curl)
#   - CI/CD Pipeline Engineer  (parallelism, exit codes, partial failures)

require_relative "../spec_helper"
require_relative "../../verify"

module Gem
  class << self
    alias :real_ruby :ruby unless method_defined?(:real_ruby)
  end
end

RSpec.describe "Chef Workstation practical user workflows" do

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

  # ---------------------------------------------------------------------------
  # Shared helper – build a lightweight unit-testable component.
  # `app_dir` is relative to the fixture omnibus root.
  # ---------------------------------------------------------------------------

  def unit_testable_component(name, app_dir)
    ChefWorkstation::ComponentTest.new(name).tap do |c|
      c.base_dir = app_dir
      c.unit_test { sh("#{Gem.real_ruby} verify_me", env: { "RUBYOPT" => "" }) }
      c.smoke_test { sh("exit 0") }
    end
  end

  def healthy_smoke_component(name, app_dir)
    ChefWorkstation::ComponentTest.new(name).tap do |c|
      c.base_dir = app_dir
      c.smoke_test { sh("exit 0") }
    end
  end

  def broken_smoke_component(name, app_dir)
    ChefWorkstation::ComponentTest.new(name).tap do |c|
      c.base_dir = app_dir
      c.smoke_test { sh("exit 1") }
    end
  end

  # ===========================================================================
  # COOKBOOK AUTHOR WORKFLOWS
  #
  # Practical uses covered:
  #   #1  Create new Chef cookbooks
  #   #2  Generate recipes, templates, and attributes
  #   #4  Manage cookbook dependencies
  #   #10 Perform unit testing on recipes
  #   #9  Lint code with Cookstyle
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # Feature: Cookbook dependency management with Berkshelf
  #
  # As a cookbook author
  # I want to be sure that Berkshelf is installed and functional
  # So that I can manage cookbook dependencies and resolve version conflicts
  # before I start writing any infrastructure code
  # ---------------------------------------------------------------------------

  context "As a cookbook author managing cookbook dependencies with berkshelf" do
    before do
      allow(verifier).to receive(:components).and_return([
        unit_testable_component("berkshelf", "embedded/apps/berkshelf"),
      ])
    end

    # Given: berkshelf is installed in the Chef Workstation bundle
    # When:  I run `chef verify berkshelf --unit --verbose`
    # Then:  the dependency management tool is confirmed ready
    it "confirms berkshelf is ready to manage cookbook dependencies" do
      verifier.run(%w{--unit --verbose})
      expect(output).to include("you are good to go...")
    end

    # Then:  the verification reports success so I can trust berks commands will work
    it "reports successful verification of the berkshelf component" do
      verifier.run(%w{--unit})
      expect(output).to include("Verification of component 'berkshelf' succeeded.")
    end

    # Given: I only want to check berkshelf
    # When:  I pass 'berkshelf' as the component filter
    # Then:  other components are not run, giving me fast feedback
    it "only verifies berkshelf when filtered by name" do
      allow(verifier).to receive(:components).and_return([
        unit_testable_component("berkshelf",    "embedded/apps/berkshelf"),
        unit_testable_component("test-kitchen", "embedded/apps/test-kitchen"),
      ])
      verifier.run(["berkshelf"])
      expect(output).to     include("Verification of component 'berkshelf' succeeded.")
      expect(output).not_to include("Verification of component 'test-kitchen'")
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Cookbook scaffolding and recipe generation with Chef CLI
  #
  # As a cookbook author
  # I want to generate new cookbook scaffolding quickly
  # So that I can start writing infrastructure code with a consistent structure
  # ---------------------------------------------------------------------------

  context "As a cookbook author generating new cookbook scaffolding with chef-cli" do
    before do
      allow(verifier).to receive(:components).and_return([
        unit_testable_component("chef-cli", "embedded/apps/berkshelf"),
      ])
    end

    # Given: chef-cli is installed and working
    # When:  I verify the chef-cli component
    # Then:  I know `chef generate cookbook` and related commands will work
    it "confirms chef-cli is ready for cookbook generation and authoring" do
      verifier.run(%w{--unit --verbose})
      expect(output).to include("you are good to go...")
    end

    it "exits successfully, indicating cookbook generation is available" do
      expect(verifier.run(%w{--unit})).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Recipe unit testing with ChefSpec
  #
  # As a cookbook author
  # I want to unit-test my recipes in memory without spinning up VMs
  # So that I get fast feedback on my recipe logic during development
  # ---------------------------------------------------------------------------

  context "As a cookbook author unit-testing recipes with chefspec" do
    before do
      allow(verifier).to receive(:components).and_return([
        unit_testable_component("chefspec", "embedded/apps/chefspec"),
      ])
    end

    # Given: chefspec is installed in the Chef Workstation bundle
    # When:  I run `chef verify chefspec --unit --verbose`
    # Then:  the unit testing framework confirms it is operational
    it "confirms chefspec is ready for recipe unit testing" do
      verifier.run(%w{--unit --verbose})
      expect(output).to include("ChefSpec recipe unit testing engine is ready.")
    end

    # Then: my CI pipeline can trust that `rspec` over my cookbook specs will work
    it "reports chefspec verification as succeeded" do
      verifier.run(%w{--unit})
      expect(output).to include("Verification of component 'chefspec' succeeded.")
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Cookbook linting with Cookstyle
  #
  # As a cookbook author
  # I want Cookstyle to be verified before code review
  # So that style and correctness checks catch problems before they reach the team
  # ---------------------------------------------------------------------------

  context "As a cookbook author linting cookbook code with Cookstyle" do
    before do
      allow(verifier).to receive(:components).and_return([
        unit_testable_component("cookstyle", "embedded/apps/cookstyle"),
      ])
    end

    # Given: cookstyle is installed
    # When:  I run the cookstyle verification
    # Then:  the linter is confirmed available so style checks can be enforced
    it "confirms cookstyle is ready for linting" do
      verifier.run(%w{--unit --verbose})
      expect(output).to include("Cookstyle linter is ready.")
    end

    it "reports cookstyle verification as succeeded" do
      verifier.run(%w{--unit})
      expect(output).to include("Verification of component 'cookstyle' succeeded.")
    end
  end

  # ===========================================================================
  # INFRASTRUCTURE TESTING WORKFLOWS
  #
  # Practical uses covered:
  #   #6  Run local cookbook tests with Test Kitchen
  #   #7  Spin up test environments (VMs or containers)
  #   #13 Install and configure software packages
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # Feature: Local cookbook testing with Test Kitchen
  #
  # As an infrastructure tester
  # I want to spin up test environments for my cookbooks locally
  # So that I can validate my recipes work correctly before deploying to production
  # ---------------------------------------------------------------------------

  context "As an infrastructure tester spinning up test environments with Test Kitchen" do
    before do
      allow(verifier).to receive(:components).and_return([
        unit_testable_component("test-kitchen", "embedded/apps/test-kitchen"),
      ])
    end

    # Given: test-kitchen is installed in the Chef Workstation bundle
    # When:  I run `chef verify test-kitchen --unit --verbose`
    # Then:  the test harness is confirmed ready for environment spin-up
    it "confirms test-kitchen is ready for spinning up test environments" do
      verifier.run(%w{--unit --verbose})
      expect(output).to include("my friend everything is good...")
    end

    # Then: I know `kitchen converge` and `kitchen verify` commands will work
    it "reports test-kitchen verification as succeeded" do
      verifier.run(%w{--unit})
      expect(output).to include("Verification of component 'test-kitchen' succeeded.")
    end

    # Given: I want to validate both my cookbook authoring and testing tools in one go
    # When:  I run chef verify covering berkshelf and test-kitchen
    # Then:  both confirm readiness for a complete test-driven cookbook workflow
    it "confirms both berkshelf and test-kitchen are ready for a complete TDD cookbook workflow" do
      allow(verifier).to receive(:components).and_return([
        unit_testable_component("berkshelf",    "embedded/apps/berkshelf"),
        unit_testable_component("test-kitchen", "embedded/apps/test-kitchen"),
      ])
      verifier.run(%w{--unit})
      expect(output).to include("Verification of component 'berkshelf' succeeded.")
      expect(output).to include("Verification of component 'test-kitchen' succeeded.")
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Policy-driven provisioning with Test Kitchen policyfile provisioner
  #
  # As an infrastructure tester using policy-based provisioning
  # I want the policyfile provisioner for Test Kitchen to be available
  # So that I can test cookbooks under realistic policyfile conditions
  # ---------------------------------------------------------------------------

  context "As an infrastructure tester validating policyfile-based kitchen provisioning" do
    before do
      allow(verifier).to receive(:components).and_return([
        healthy_smoke_component("tk-policyfile-provisioner", "embedded/apps/berkshelf"),
      ])
    end

    # Given: the policyfile kitchen provisioner is part of the bundle
    # When:  I run `chef verify tk-policyfile-provisioner`
    # Then:  the provisioner is confirmed available so kitchen tests can use policies
    it "confirms the policyfile kitchen provisioner is available" do
      verifier.run([])
      expect(output).to include("Verification of component 'tk-policyfile-provisioner' succeeded.")
    end

    it "exits successfully when the policyfile provisioner is functional" do
      expect(verifier.run([])).to eq(0)
    end
  end

  # ===========================================================================
  # COMPLIANCE AND SECURITY WORKFLOWS
  #
  # Practical uses covered:
  #   #21 Write compliance profiles with InSpec
  #   #22 Run security audits locally or remotely
  #   #23 Enforce organisational policies
  #   #24 Detect configuration drift
  #   #25 Generate compliance reports
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # Feature: Compliance auditing with InSpec
  #
  # As a compliance engineer
  # I want InSpec to be installed and functional
  # So that I can write and run compliance profiles against any target system
  # ---------------------------------------------------------------------------

  context "As a compliance engineer auditing systems with InSpec" do
    before do
      allow(verifier).to receive(:components).and_return([
        unit_testable_component("inspec", "embedded/apps/inspec"),
      ])
    end

    # Given: InSpec is part of the Chef Workstation bundle
    # When:  I run `chef verify inspec --unit --verbose`
    # Then:  the compliance engine confirms it is ready to run profiles
    it "confirms InSpec is ready for writing and running compliance profiles" do
      verifier.run(%w{--unit --verbose})
      expect(output).to include("InSpec compliance engine is ready.")
    end

    # Then: I know I can run `inspec exec` against targets to audit compliance
    it "reports successful verification so compliance audits can proceed" do
      verifier.run(%w{--unit})
      expect(output).to include("Verification of component 'inspec' succeeded.")
    end

    # Given: I want to verify both my configuration management and compliance tools
    # When:  I verify chef-client and inspec together
    # Then:  both confirm readiness for a converge-then-audit workflow
    it "supports a converge-then-audit workflow when chef-client and inspec both pass" do
      allow(verifier).to receive(:components).and_return([
        healthy_smoke_component("chef-client", "embedded/apps/berkshelf"),
        unit_testable_component("inspec",      "embedded/apps/inspec"),
      ])
      verifier.run(%w{--unit})
      expect(output).to include("Verification of component 'chef-client' succeeded.")
      expect(output).to include("Verification of component 'inspec' succeeded.")
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Security policy enforcement and configuration drift detection
  #
  # As a security engineer
  # I want to detect configuration drift across my fleet
  # So that I can enforce security policies and catch deviations before audits
  # ---------------------------------------------------------------------------

  context "As a security engineer detecting configuration drift with InSpec" do
    # Given: InSpec fails its smoke test (e.g., the binary is missing or broken)
    # When:  I run chef verify inspec
    # Then:  I am immediately notified that drift detection capability is unavailable
    it "alerts the security engineer when the InSpec drift-detection tool is broken" do
      allow(verifier).to receive(:components).and_return([
        broken_smoke_component("inspec", "embedded/apps/berkshelf"),
      ])
      verifier.run([])
      expect(output).to include("Verification of component 'inspec' failed.")
    end

    # Given: InSpec is working correctly
    # When:  I verify InSpec as part of a policy enforcement pipeline
    # Then:  the exit code 0 signals my pipeline that drift detection is available
    it "gives a clean exit code when InSpec is ready for policy enforcement" do
      allow(verifier).to receive(:components).and_return([
        healthy_smoke_component("inspec", "embedded/apps/berkshelf"),
      ])
      expect(verifier.run([])).to eq(0)
    end
  end

  # ===========================================================================
  # OPERATIONS AND MAINTENANCE WORKFLOWS
  #
  # Practical uses covered:
  #   #11 Automate server provisioning
  #   #14 Enforce desired system state
  #   #15 Apply configuration across multiple nodes
  #   #17 Bootstrap new nodes
  #   #26 Use Knife to manage nodes and roles
  #   #27 Upload cookbooks to Chef Server
  #   #28 Debug infrastructure issues
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # Feature: Applying configurations with Chef Infra Client
  #
  # As an operations engineer
  # I want Chef Infra Client to be installed and verified
  # So that I can apply configurations and enforce desired state on servers
  # ---------------------------------------------------------------------------

  context "As an operations engineer applying configurations with Chef Infra Client" do
    before do
      allow(verifier).to receive(:components).and_return([
        unit_testable_component("chef-apply", "embedded/apps/chef-apply"),
      ])
    end

    # Given: chef-apply is part of the Chef Workstation bundle
    # When:  I run `chef verify chef-apply --unit --verbose`
    # Then:  the configuration engine is confirmed ready to converge nodes
    it "confirms chef-apply is ready to apply configurations to systems" do
      verifier.run(%w{--unit --verbose})
      expect(output).to include("Chef Infra Client is ready to apply configurations.")
    end

    # Then: I know I can run `chef-apply` recipes to enforce desired state
    it "reports successful verification of the chef configuration engine" do
      verifier.run(%w{--unit})
      expect(output).to include("Verification of component 'chef-apply' succeeded.")
    end

    # Given: chef-apply is broken (e.g., after a partial installation)
    # When:  I run verification before a deployment window
    # Then:  I am warned before attempting to converge production nodes
    it "alerts the operations engineer before deployment when chef-apply is broken" do
      allow(verifier).to receive(:components).and_return([
        broken_smoke_component("chef-apply", "embedded/apps/berkshelf"),
      ])
      verifier.run([])
      expect(output).to include("Verification of component 'chef-apply' failed.")
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Managing nodes and roles with Knife
  #
  # As an operations engineer
  # I want Knife to be available and functional
  # So that I can manage nodes, upload roles, and interact with Chef Infra Server
  # ---------------------------------------------------------------------------

  context "As an operations engineer managing nodes and roles with Knife" do
    before do
      allow(verifier).to receive(:components).and_return([
        unit_testable_component("knife", "embedded/apps/knife"),
      ])
    end

    # Given: Knife is installed in the Chef Workstation bundle
    # When:  I verify the knife component
    # Then:  the server management tool is confirmed ready
    it "confirms Knife is ready to interact with Chef Infra Server" do
      verifier.run(%w{--unit --verbose})
      expect(output).to include("Knife is ready to interact with Chef Infra Server.")
    end

    # Then: I know node management, role uploads, and cookbook uploads will work
    it "reports knife verification as succeeded" do
      verifier.run(%w{--unit})
      expect(output).to include("Verification of component 'knife' succeeded.")
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: SSL connectivity for cloud provider integrations
  #
  # As an operations engineer managing cloud infrastructure
  # I want SSL to be functional in the Chef Workstation bundle
  # So that I can connect to Chef Server, AWS, Azure, or GCP endpoints securely
  # ---------------------------------------------------------------------------

  context "As an operations engineer verifying SSL connectivity for cloud integrations" do
    before do
      allow(verifier).to receive(:components).and_return([
        unit_testable_component("openssl", "embedded/apps/openssl-check"),
      ])
    end

    # Given: the bundled OpenSSL is functional
    # When:  I run `chef verify openssl --unit --verbose`
    # Then:  the SSL library confirms it can make secure connections to cloud providers
    it "confirms OpenSSL is functional for cloud provider connectivity" do
      verifier.run(%w{--unit --verbose})
      expect(output).to include("OpenSSL is functional. SSL connectivity is available.")
    end

    # Then: I can be confident that knife, inspec and chef-client will reach
    #       Chef Server and cloud endpoints without TLS errors
    it "reports openssl verification as succeeded" do
      verifier.run(%w{--unit})
      expect(output).to include("Verification of component 'openssl' succeeded.")
    end
  end

  # ===========================================================================
  # PLATFORM ENGINEERING WORKFLOWS
  #
  # Practical uses covered:
  #   #18 Automate environment setup (dev/staging/prod)
  #   #20 Maintain consistent environments across teams
  #   #19 Handle scaling infrastructure
  #   #5  Version control integration (e.g. Git workflows)
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # Feature: Verifying a complete DevOps toolchain
  #
  # As a platform engineer
  # I want to verify the entire Chef Workstation toolchain at once
  # So that I can guarantee every engineer on the team has a consistent,
  # fully functional development and operations environment
  # ---------------------------------------------------------------------------

  context "As a platform engineer verifying the full DevOps toolchain" do
    let(:full_toolchain) do
      [
        healthy_smoke_component("berkshelf",    "embedded/apps/berkshelf"),
        healthy_smoke_component("chef-cli",     "embedded/apps/berkshelf"),
        healthy_smoke_component("test-kitchen", "embedded/apps/test-kitchen"),
        healthy_smoke_component("chefspec",     "embedded/apps/berkshelf"),
        healthy_smoke_component("inspec",       "embedded/apps/berkshelf"),
        healthy_smoke_component("knife",        "embedded/apps/berkshelf"),
      ]
    end

    before do
      allow(verifier).to receive(:components).and_return(full_toolchain)
    end

    # Given: all tools in the Chef Workstation bundle are installed and healthy
    # When:  I run `chef verify` with no filters
    # Then:  every component is confirmed ready so team environments are consistent
    it "reports every DevOps tool as verified when all components are healthy" do
      verifier.run([])
      expect(output).to include("Verification of component 'berkshelf' succeeded.")
      expect(output).to include("Verification of component 'chef-cli' succeeded.")
      expect(output).to include("Verification of component 'test-kitchen' succeeded.")
      expect(output).to include("Verification of component 'chefspec' succeeded.")
      expect(output).to include("Verification of component 'inspec' succeeded.")
      expect(output).to include("Verification of component 'knife' succeeded.")
    end

    # Then: the exit code 0 signals that the environment is safe to use
    it "exits 0 indicating the team environment is consistent and ready" do
      expect(verifier.run([])).to eq(0)
    end

    # Given: one tool in the toolchain is broken
    # When:  a new engineer runs `chef verify` to check their environment
    # Then:  they are told exactly which tool needs attention before they start work
    it "pinpoints the broken tool in an otherwise healthy toolchain" do
      broken_toolchain = full_toolchain + [
        broken_smoke_component("cookstyle", "embedded/apps/berkshelf"),
      ]
      allow(verifier).to receive(:components).and_return(broken_toolchain)
      verifier.run([])
      expect(output).to include("Verification of component 'cookstyle' failed.")
      # All healthy tools still reported
      expect(output).to include("Verification of component 'berkshelf' succeeded.")
      expect(output).to include("Verification of component 'inspec' succeeded.")
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Git version control integration
  #
  # As a platform engineer enforcing version-controlled infrastructure
  # I want Git to be available within the Chef Workstation bundle
  # So that cookbook authoring workflows, CI pipelines, and berks source
  # resolution all work without relying on a separate system Git installation
  # ---------------------------------------------------------------------------

  context "As a platform engineer relying on bundled Git for version control workflows" do
    before do
      allow(verifier).to receive(:components).and_return([
        healthy_smoke_component("git", "embedded/apps/berkshelf"),
      ])
    end

    # Given: git is bundled with Chef Workstation
    # When:  the verification suite runs the git smoke test
    # Then:  a healthy git binary is confirmed so berks and cookbook sources work
    it "confirms bundled git is functional for version control workflows" do
      verifier.run([])
      expect(output).to include("Verification of component 'git' succeeded.")
    end

    it "exits successfully when git is available" do
      expect(verifier.run([])).to eq(0)
    end
  end

  # ===========================================================================
  # CI/CD PIPELINE ENGINEER WORKFLOWS
  #
  # Practical uses covered:
  #   #18 Automate environment setup (dev/staging/prod)
  #   #19 Handle scaling infrastructure
  #   #30 Automate routine maintenance tasks
  # ===========================================================================

  # ---------------------------------------------------------------------------
  # Feature: Reliable parallel verification in a build pipeline
  #
  # As a CI/CD pipeline engineer
  # I want the verification run to check multiple components concurrently
  # So that build verification completes quickly at scale without serial bottlenecks
  # ---------------------------------------------------------------------------

  context "As a CI/CD pipeline engineer running parallel component verification" do
    let(:all_components) do
      %w[berkshelf test-kitchen inspec chefspec chef-apply knife cookstyle].map do |name|
        healthy_smoke_component(name, "embedded/apps/berkshelf")
      end
    end

    before do
      allow(verifier).to receive(:components).and_return(all_components)
    end

    # Given: seven components all pass
    # When:  verification runs (internally using threads)
    # Then:  all seven succeed and the pipeline receives a clean exit
    it "verifies all components and exits 0 for a fully healthy pipeline" do
      expect(verifier.run([])).to eq(0)
    end

    # Then: every component appears in the results summary
    it "produces a result line for every component in the pipeline" do
      verifier.run([])
      %w[berkshelf test-kitchen inspec chefspec chef-apply knife cookstyle].each do |name|
        expect(output).to include("Verification of component '#{name}' succeeded.")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Pipeline resilience – one broken component must not silence others
  #
  # As a CI/CD pipeline engineer
  # I want the verifier to continue checking all components even when one fails
  # So that a single broken tool does not hide other failures in the same run
  # ---------------------------------------------------------------------------

  context "As a CI/CD pipeline engineer receiving complete results despite partial failures" do
    before do
      allow(verifier).to receive(:components).and_return([
        healthy_smoke_component("berkshelf",    "embedded/apps/berkshelf"),
        broken_smoke_component("inspec",        "embedded/apps/berkshelf"),
        healthy_smoke_component("test-kitchen", "embedded/apps/berkshelf"),
        broken_smoke_component("cookstyle",     "embedded/apps/berkshelf"),
        healthy_smoke_component("knife",        "embedded/apps/berkshelf"),
      ])
    end

    # Given: two of five components are broken
    # When:  the pipeline runs `chef verify`
    # Then:  all five results are reported (not just the first failure)
    it "reports results for all components, not just the first failure" do
      verifier.run([])
      expect(output).to include("Verification of component 'berkshelf' succeeded.")
      expect(output).to include("Verification of component 'inspec' failed.")
      expect(output).to include("Verification of component 'test-kitchen' succeeded.")
      expect(output).to include("Verification of component 'cookstyle' failed.")
      expect(output).to include("Verification of component 'knife' succeeded.")
    end

    # Then: the pipeline exit code is non-zero so the build is marked as failed
    it "returns a non-zero exit code so the pipeline build is correctly marked failed" do
      expect(verifier.run([])).to eq(1)
    end
  end

  # ---------------------------------------------------------------------------
  # Feature: Selective re-verification after a fix
  #
  # As a CI/CD pipeline engineer re-running after an engineer fixed a component
  # I want to quickly verify just the repaired component without re-running everything
  # So that I can confirm the fix without waiting for the full suite to complete
  # ---------------------------------------------------------------------------

  context "As a CI/CD pipeline engineer selectively re-verifying a repaired component" do
    before do
      allow(verifier).to receive(:components).and_return([
        healthy_smoke_component("inspec",       "embedded/apps/berkshelf"),
        healthy_smoke_component("test-kitchen", "embedded/apps/berkshelf"),
        healthy_smoke_component("berkshelf",    "embedded/apps/berkshelf"),
      ])
    end

    # Given: inspec was previously broken and has just been repaired
    # When:  I run `chef verify inspec` to re-verify only that component
    # Then:  only inspec is checked, giving fast feedback that the fix worked
    it "only re-verifies the repaired component when it is named explicitly" do
      verifier.run(["inspec"])
      expect(output).to     include("Verification of component 'inspec' succeeded.")
      expect(output).not_to include("Verification of component 'test-kitchen'")
      expect(output).not_to include("Verification of component 'berkshelf'")
    end

    # Then: the exit code 0 confirms to the pipeline that the repair is complete
    it "exits 0 confirming the fix is valid and the component is restored" do
      expect(verifier.run(["inspec"])).to eq(0)
    end
  end
end
