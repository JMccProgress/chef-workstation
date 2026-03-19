# Chef Workstation Verification — developer guide

This directory contains two distinct but related things:

1. **The `chef verify` runner** — a post-install smoke-test suite invoked by CI
   after a real Chef Workstation package is installed on a target machine.
2. **An RSpec test suite for the runner itself** — BDD-style specs that verify
   the behaviour of the verification framework without needing a full
   installation.

---

## Table of contents

- [Background and structure](#background-and-structure)
- [Prerequisites](#prerequisites)
- [Running the RSpec test suite (recommended starting point)](#running-the-rspec-test-suite)
  - [Run everything](#run-everything)
  - [Run only unit specs](#run-only-unit-specs)
  - [Run only feature specs](#run-only-feature-specs)
  - [Run a single spec file](#run-a-single-spec-file)
  - [Run a single example by line number](#run-a-single-example-by-line-number)
  - [Filter by description text](#filter-by-description-text)
  - [Stop on the first failure](#stop-on-the-first-failure)
  - [See full test names while running](#see-full-test-names-while-running)
  - [Check code coverage](#check-code-coverage)
- [Running the post-install verification suite](#running-the-post-install-verification-suite)
  - [Linux and macOS](#linux-and-macos)
  - [Windows](#windows)
  - [Available flags](#available-flags)
- [Spec file reference](#spec-file-reference)
- [Adding a new component](#adding-a-new-component)
- [Troubleshooting](#troubleshooting)

---

## Background and structure

```
omnibus/verification/
├── run.rb                   Entry point: parses flags and calls verify.rb
├── verify.rb                Defines every Chef Workstation component and
│                            the verification framework (Verify class)
├── component_test.rb        ComponentTest class — wraps a single bundled tool
│
└── spec/
    ├── spec_helper.rb       RSpec configuration, shared helpers, SimpleCov
    │
    ├── unit/
    │   ├── verify_spec.rb           Unit tests for Verify (29 examples)
    │   ├── component_test_spec.rb   Unit tests for ComponentTest (27 examples)
    │   └── fixtures/
    │       └── eg_omnibus_dir/      Fake Omnibus install trees used by specs
    │           ├── valid/           A complete, working fixture layout
    │           ├── missing_component/  Layout missing one component dir
    │           └── missing_apps/    Layout missing the apps directory entirely
    │
    └── features/
        ├── chef_verify_feature_spec.rb           (18 examples)
        │   BDD specs for core verifier behaviour — banner, component list,
        │   omnibus path resolution, unit/smoke/integration test execution,
        │   output format, filtering, and verbose mode.
        │
        ├── workstation_workflows_feature_spec.rb  (37 examples)
        │   BDD specs mapped to practical user roles: Cookbook Author,
        │   Infrastructure Tester, Compliance Engineer, Operations Engineer,
        │   Platform Engineer, CI/CD Pipeline Engineer.
        │
        └── workstation_integrity_feature_spec.rb  (71 examples)
            Deeper integrity and integration coverage:
            • Functional workflow simulations via real fixture scripts
              (cookbook generation, Cookstyle, InSpec, Knife) — no mocking.
            • Component registry discovery (class-level, no instance stubs).
            • Packaging and install integrity (assert_present!, missing dirs,
              non-executable scripts).
            • Edge cases: unknown filter, partial filter, exception propagation,
              all-fail no-early-exit.
            • Strict output contract: exact status-line regex, 45-char separator,
              integer exit codes, stdout vs stderr separation.
            • Parallel execution safety: 5 concurrent pass, 5 concurrent fail,
              mixed pass/fail.
            • Cross-platform path handling: File.join, PATH_SEPARATOR.
```

> **Scope note.** The RSpec suite validates the *framework* — it does not
> replace a full end-to-end system test on a real Chef Workstation installation.
> The post-install suite (`run.rb`) does the real thing.

---

## Prerequisites

You need **Ruby** (any version ≥ 2.7) and **Bundler** installed.

### 1 — Install Bundler (once, if not already installed)

```bash
gem install bundler
```

### 2 — Install project gems (once, or after changing `Gemfile`)

Run this from the **repository root** (not from inside `omnibus/verification/`):

```bash
# from chef-workstation/
bundle install
```

This installs `rspec`, `chef-cli`, `simplecov`, and `chefstyle` into the
project's bundle.

> **Tip:** If you get a `bundler: command not found` error, the gem binary
> directory may not be on your PATH.  Try `gem install bundler --user-install`
> and add the printed path to your `PATH`.

---

## Running the RSpec test suite

All commands below must be run from the **repository root**
(`chef-workstation/`), not from inside `omnibus/verification/`.

### Run everything

```bash
bundle exec rspec omnibus/verification/spec/
```

Expected output: **182 examples, 0 failures**

### Run only unit specs

Unit specs exercise `verify.rb` and `component_test.rb` in isolation with
heavy mocking.  They are fast (< 5 seconds) and have no external dependencies.

```bash
bundle exec rspec omnibus/verification/spec/unit/
```

### Run only feature specs

Feature specs exercise the verification framework end-to-end (with a fixture
Omnibus directory) and include real subprocess execution via fixture scripts.

```bash
bundle exec rspec omnibus/verification/spec/features/
```

### Run a single spec file

Pass the file path directly to rspec:

```bash
bundle exec rspec omnibus/verification/spec/features/workstation_integrity_feature_spec.rb
bundle exec rspec omnibus/verification/spec/features/workstation_workflows_feature_spec.rb
bundle exec rspec omnibus/verification/spec/features/chef_verify_feature_spec.rb
bundle exec rspec omnibus/verification/spec/unit/verify_spec.rb
bundle exec rspec omnibus/verification/spec/unit/component_test_spec.rb
```

### Run a single example by line number

Find the line number of the `it "..."` block you want to run, then:

```bash
bundle exec rspec omnibus/verification/spec/features/workstation_integrity_feature_spec.rb:90
```

Replace `90` with the actual line number.

### Filter by description text

Use `-e` to run every example whose description contains a given string
(case-sensitive):

```bash
# Run every example that mentions "exit code"
bundle exec rspec omnibus/verification/spec/ -e "exit code"

# Run every example that mentions "inspec"
bundle exec rspec omnibus/verification/spec/ -e "inspec"

# Run every example that mentions "parallel"
bundle exec rspec omnibus/verification/spec/ -e "concurrent"
```

### Stop on the first failure

Useful when debugging a single broken test — avoid waiting for the whole suite:

```bash
bundle exec rspec omnibus/verification/spec/ --fail-fast
```

### See full test names while running

The default output is a dot-per-example.  Switch to `documentation` format to
see the full BDD description hierarchy:

```bash
bundle exec rspec omnibus/verification/spec/ --format documentation
```

Or for a single file:

```bash
bundle exec rspec omnibus/verification/spec/features/workstation_integrity_feature_spec.rb \
  --format documentation
```

Example output:

```
Chef Workstation integrity and integration
  Functional workflow simulations (ComponentTest-level, no mocking)
    chef generate cookbook output simulation
      exits successfully
      reports the cookbook name being created
      reports generation of metadata.rb
      ...
```

### Check code coverage

SimpleCov runs automatically whenever you run the suite.  After the run, open
the generated HTML report:

```bash
# macOS
open coverage/index.html

# Linux (with xdg-open)
xdg-open coverage/index.html

# Or just read the summary printed to the terminal after rspec finishes:
#   Line Coverage: 93.36% (1210 / 1296)
```

The CI pipeline requires coverage ≥ 79 % or the build fails.

---

## Running the post-install verification suite

> **This requires a real Chef Workstation package to be installed** on the
> machine.  Use this after running the installer, not during development.

The post-install suite calls `run.rb` using the Ruby bundled *inside* the
Chef Workstation package — not the system Ruby you use for the RSpec suite.

### Linux and macOS

```bash
# Default: smoke tests only
/opt/chef-workstation/embedded/bin/ruby omnibus/verification/run.rb

# Also run unit tests for each component
/opt/chef-workstation/embedded/bin/ruby omnibus/verification/run.rb --unit

# Also run integration tests (may mutate system state — development machines only)
/opt/chef-workstation/embedded/bin/ruby omnibus/verification/run.rb --integration

# Verbose: print all test output, not just failures
/opt/chef-workstation/embedded/bin/ruby omnibus/verification/run.rb --verbose

# Verify one specific component only (e.g., inspec)
/opt/chef-workstation/embedded/bin/ruby omnibus/verification/run.rb inspec

# Verify a subset of components
/opt/chef-workstation/embedded/bin/ruby omnibus/verification/run.rb inspec berkshelf chef-client

# Combine flags
/opt/chef-workstation/embedded/bin/ruby omnibus/verification/run.rb --unit --verbose inspec
```

### Windows

```powershell
# Default: smoke tests only
C:\opscode\chef-workstation\embedded\bin\ruby.exe omnibus\verification\run.rb

# Also run unit tests
C:\opscode\chef-workstation\embedded\bin\ruby.exe omnibus\verification\run.rb --unit

# Verbose output
C:\opscode\chef-workstation\embedded\bin\ruby.exe omnibus\verification\run.rb --verbose

# Verify a specific component
C:\opscode\chef-workstation\embedded\bin\ruby.exe omnibus\verification\run.rb inspec
```

### Available flags

| Flag | What it does |
|---|---|
| _(none)_ | Run smoke tests only (fast, safe, default) |
| `--unit` | Also run unit tests embedded in each component |
| `--integration` | Also run integration tests (may affect system state) |
| `--verbose` | Print full test output even for passing components |
| `--omnibus-dir PATH` | Override the default `/opt/chef-workstation` install path |
| `component-name ...` | Verify only the named component(s) instead of all |

Exit code is **0** on full success, **1** if any component fails.

---

## Spec file reference

| File | Type | Examples | What it covers |
|---|---|---|---|
| `spec/unit/verify_spec.rb` | Unit | 29 | `Verify` class — component registry, omnibus path resolution, unit/smoke/integration test execution, filtering, output format |
| `spec/unit/component_test_spec.rb` | Unit | 27 | `ComponentTest` class — `sh`, `sh!`, `bin`, `embedded_bin`, `assert_present!`, path helpers |
| `spec/features/chef_verify_feature_spec.rb` | Feature (BDD) | 18 | Core verifier behaviour from a user perspective: banner, component list, omnibus path resolution, verbose mode |
| `spec/features/workstation_workflows_feature_spec.rb` | Feature (BDD) | 37 | Practical user workflows across six roles: Cookbook Author, Infrastructure Tester, Compliance Engineer, Operations Engineer, Platform Engineer, CI/CD Pipeline Engineer |
| `spec/features/workstation_integrity_feature_spec.rb` | Integration (BDD) | 71 | Real subprocess executions via fixture scripts, packaging integrity, edge cases, strict output contract, parallel safety, cross-platform paths |

**Total: 182 examples**

---

## Adding a new component

1. Open `omnibus/verification/verify.rb`.
2. Follow the pattern of an existing `add_component` block, e.g.:

   ```ruby
   add_component "my-tool" do |c|
     c.base_dir = "embedded/apps/my-tool"
     c.smoke_test { sh("#{bin("my-tool")} --version") }
   end
   ```

3. Create a fixture directory for the new component so the RSpec suite can
   find it:

   ```
   omnibus/verification/spec/unit/fixtures/eg_omnibus_dir/valid/embedded/apps/my-tool/verify_me
   ```

   `verify_me` must be an executable Ruby script that exits 0 on success.

4. Add a `verify_me` script:

   ```ruby
   #!/usr/bin/env ruby
   puts "my-tool is OK"
   exit 0
   ```

   Make it executable:

   ```bash
   chmod +x omnibus/verification/spec/unit/fixtures/eg_omnibus_dir/valid/embedded/apps/my-tool/verify_me
   ```

5. Run the suite and confirm there are no regressions:

   ```bash
   bundle exec rspec omnibus/verification/spec/
   ```

---

## Troubleshooting

### `bundler: command not found`

Bundler is not on your PATH.  Install it and add its bin directory:

```bash
gem install bundler --user-install
# Ruby will print something like:
#   Successfully installed bundler-2.x.x
#   1 gem installed
#   WARNING: You don't have /home/yourname/.local/share/gem/ruby/3.2.0/bin in your PATH

export PATH="$(ruby -e 'puts Gem.user_dir')/bin:$PATH"
```

Add that `export` line to your shell's config file (`.bashrc`, `.zshrc`, etc.)
to make it permanent.

### `LoadError: cannot load such file -- chef-cli`

The gems are not installed yet.  Run `bundle install` from the repo root.

### `OmnibusInstallNotFound` during a spec run

A spec is trying to resolve the Omnibus root using the *real* `Gem.ruby` path
instead of the fixture path.  Check that the spec stubs `Gem.ruby`:

```ruby
allow(Gem).to receive(:ruby).and_return(
  File.join(fixtures_path, "eg_omnibus_dir/valid/embedded/bin/ruby")
)
```

### Coverage is below 79 %

The CI pipeline enforces a minimum of 79 % line coverage.  Run the full suite
and open `coverage/index.html` to see which lines are not exercised, then add
tests for the uncovered paths.

### A fixture `verify_me` script fails with `Permission denied`

The script file may have lost its execute permission (e.g. after a `git clone`
on a system that strips permissions).  Fix it:

```bash
chmod +x omnibus/verification/spec/unit/fixtures/eg_omnibus_dir/valid/embedded/apps/*/verify_me
chmod +x omnibus/verification/spec/unit/fixtures/eg_omnibus_dir/valid/embedded/apps/berkshelf/*_sim
```
