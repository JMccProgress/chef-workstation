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

require_relative "../spec_helper"
require_relative "../../component_test"
require "pathname"

describe ChefWorkstation::ComponentTest do

  let(:component) do
    ChefWorkstation::ComponentTest.new("berkshelf").tap do |c|
      c.base_dir = "berkshelf"
    end
  end

  it "defines the component" do
    expect(component.name).to eq("berkshelf")
  end

  it "sets the component base directory" do
    expect(component.base_dir).to eq("berkshelf")
  end

  it "defines a default unit test" do
    expect(component.run_unit_test.exitstatus).to eq(0)
    expect(component.run_unit_test.stdout).to eq("")
    expect(component.run_unit_test.stderr).to eq("")
  end

  it "defines a default integration test" do
    expect(component.run_integration_test.exitstatus).to eq(0)
    expect(component.run_integration_test.stdout).to eq("")
    expect(component.run_integration_test.stderr).to eq("")
  end

  it "defines a default smoke test" do
    expect(component.run_smoke_test.exitstatus).to eq(0)
    expect(component.run_smoke_test.stdout).to eq("")
    expect(component.run_smoke_test.stderr).to eq("")
  end

  context "with basic tests defined" do

    let(:result) { {} }

    before do
      # capture a reference to results hash so we can use it in tests.
      result_hash = result
      component.tap do |c|
        c.unit_test { result_hash[:unit_test] = true }
        c.integration_test { result_hash[:integration_test] = true }
        c.smoke_test { result_hash[:smoke_test] = true }
      end
    end

    it "defines a unit test block" do
      component.run_unit_test
      expect(result[:unit_test]).to be true
    end

    it "defines an integration test block" do
      component.run_integration_test
      expect(result[:integration_test]).to be true
    end

    it "defines a smoke test block" do
      component.run_smoke_test
      expect(result[:smoke_test]).to be true
    end

  end

  context "with tests that shell out to commands" do

    let(:omnibus_root) { File.join(fixtures_path, "eg_omnibus_dir/valid/") }

    before do
      component.tap do |c|
        # Have to set omnibus dir so command can run with correct cwd
        c.omnibus_root = omnibus_root

        c.base_dir = "embedded/apps/berkshelf"

        c.unit_test { sh("true") }

        c.integration_test { sh("ruby -e 'puts Dir.pwd'", env: { "RUBYOPT" => "" }) }

        c.smoke_test { run_in_tmpdir("ruby -e 'puts Dir.pwd'", env: { "RUBYOPT" => "" }) }
      end
    end

    it "shells out and returns the shell out object" do
      expect(component.run_unit_test.exitstatus).to eq(0)
      expect(component.run_unit_test.stdout).to eq("")
      expect(component.run_unit_test.stderr).to eq("")
    end

    it "runs the command in the app's root" do
      result = component.run_integration_test
      expected_path = Pathname.new(File.join(omnibus_root, "embedded/apps/berkshelf")).realpath
      expect(Pathname.new(result.stdout.strip).realpath).to eq(expected_path)
    end

    it "runs commands in a temporary directory when specified" do
      result = component.run_smoke_test

      parent_of_cwd = Pathname.new(result.stdout.strip).parent.realpath
      tempdir = Pathname.new(Dir.tmpdir).realpath
      expect(parent_of_cwd).to eq(tempdir)
    end

  end

  # Zoomed-in unit tests for individual methods
  context "zoomed-in tests for individual methods" do

    let(:omnibus_root) { File.join(fixtures_path, "eg_omnibus_dir/valid/") }

    before do
      component.omnibus_root = omnibus_root
      component.base_dir = "embedded/apps/berkshelf"
    end

    describe "#bin" do
      it "returns the path to a binary in the omnibus bin dir" do
        result = component.bin("berks")
        expect(result).to include("berks")
        expect(result).to include(omnibus_root)
      end
    end

    describe "#embedded_bin" do
      it "returns the path to a binary in the omnibus embedded bin dir" do
        result = component.embedded_bin("ruby")
        expect(result).to include("ruby")
        expect(result).to include("embedded")
      end
    end

    describe "#sh!" do
      it "returns the result when the command succeeds" do
        result = component.sh!("true")
        expect(result.exitstatus).to eq(0)
      end

      it "raises an error when the command fails" do
        expect { component.sh!("false") }.to raise_error(Mixlib::ShellOut::ShellCommandFailed)
      end
    end

    describe "#fail_if_exit_zero" do
      it "raises an error when the command exits zero" do
        expect { component.fail_if_exit_zero("true", "should have failed") }.to raise_error("should have failed")
      end

      it "returns a passing result when the command exits non-zero" do
        result = component.fail_if_exit_zero("false")
        expect(result.exitstatus).to eq(0)
      end
    end

    describe "#nix_platform_native_bin_dir" do
      it "returns a string path for the native bin directory" do
        result = component.nix_platform_native_bin_dir
        expect(result).to be_a(String)
        expect(result).to start_with("/usr")
      end
    end

    describe "#omnibus_root" do
      it "raises an error when omnibus_root is not set" do
        c = ChefWorkstation::ComponentTest.new("test_component")
        c.base_dir = "somedir"
        expect { c.omnibus_root }.to raise_error(/omnibus_root.*must be set/)
      end
    end

    describe "#omnibus_path" do
      it "returns a PATH-style string containing the omnibus bin directories" do
        result = component.omnibus_path
        expect(result).to include(File::PATH_SEPARATOR)
        expect(result).to include("embedded")
      end
    end

    describe "#component_path" do
      it "raises an error when neither base_dir nor gem_base_dir is defined" do
        c = ChefWorkstation::ComponentTest.new("test_component")
        c.omnibus_root = omnibus_root
        expect { c.component_path }.to raise_error(/base_dir.*or.*gem_base_dir.*must be defined/)
      end

      it "uses gem_base_dir when base_dir is not set" do
        c = ChefWorkstation::ComponentTest.new("test_component")
        c.omnibus_root = omnibus_root
        fake_gem = double("gem_spec", gem_dir: "/path/to/gem")
        allow(Gem::Specification).to receive(:find_by_name).and_return(fake_gem)
        c.gem_base_dir = "some-gem"
        expect(c.component_path).to eq("/path/to/gem")
      end
    end

    describe "#gem_base_dir" do
      it "returns nil when no gem name is set" do
        c = ChefWorkstation::ComponentTest.new("test_component")
        expect(c.gem_base_dir).to be_nil
      end

      it "returns the gem directory when the gem is installed" do
        c = ChefWorkstation::ComponentTest.new("test_component")
        fake_gem = double("gem_spec", gem_dir: "/path/to/gem")
        allow(Gem::Specification).to receive(:find_by_name).with("some-gem").and_return(fake_gem)
        c.gem_base_dir = "some-gem"
        expect(c.gem_base_dir).to eq("/path/to/gem")
      end

      it "falls back to prerelease version lookup when no stable version is found" do
        c = ChefWorkstation::ComponentTest.new("test_component")
        fake_gem = double("gem_spec", gem_dir: "/path/to/prerelease-gem")
        allow(Gem::Specification).to receive(:find_by_name).with("some-gem").and_return(nil)
        allow(Gem::Specification).to receive(:find_by_name).with("some-gem", ">= 0.a").and_return(fake_gem)
        c.gem_base_dir = "some-gem"
        expect(c.gem_base_dir).to eq("/path/to/prerelease-gem")
      end
    end

    describe "#assert_present!" do
      it "raises MissingComponentError when the component path does not exist" do
        c = ChefWorkstation::ComponentTest.new("missing_component")
        c.omnibus_root = omnibus_root
        c.base_dir = "nonexistent_dir"
        expect { c.assert_present! }.to raise_error(ChefWorkstation::MissingComponentError)
      end

      it "raises MissingComponentError when gem loading fails" do
        c = ChefWorkstation::ComponentTest.new("bad_gem_component")
        allow(c).to receive(:component_path).and_raise(Gem::LoadError.new("gem not found"))
        expect { c.assert_present! }.to raise_error(ChefWorkstation::MissingComponentError)
      end
    end

  end
end
