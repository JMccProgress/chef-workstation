# Stop script execution when a non-terminating error occurs
$ErrorActionPreference = "Stop"

$channel = "$Env:CHANNEL"
If ([string]::IsNullOrEmpty($channel)) { $channel = "unstable" }

$product = "$Env:PRODUCT"
If ([string]::IsNullOrEmpty($product)) { $product = "chef-workstation" }

$version = "$Env:VERSION"
If ([string]::IsNullOrEmpty($version)) { $version = "latest" }

$package_file = "$Env:PACKAGE_FILE"
If ([string]::IsNullOrEmpty($package_file)) { $package_file = "" }

If ($package_file -eq "") {
  Write-Output "--- Installing $channel $product $version"
  $package_file = $(.omnibus-buildkite-plugin\install-omnibus-product.ps1 -Product "$product" -Channel "$channel" -Version "$version" | Select-Object -Last 1)
} 
Else {
  Write-Output "--- Installing $product $version"
  $package_file = $(.omnibus-buildkite-plugin\install-omnibus-product.ps1 -Package "$package_file" -Product "$product" -Version "$version" | Select-Object -Last 1)
}

Write-Output "--- Verifying omnibus package is signed"
C:\opscode\omnibus-toolchain\bin\check-omnibus-package-signed.ps1 "$package_file"

Write-Output "--- Running verification for $channel $product $version"

# reload Env:PATH to ensure it gets any changes that the install made (e.g. C:\opscode\chef-workstation\bin\ )
$Env:PATH = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

# Ensure user variables are set in git config
git config --global user.email "you@example.com"
git config --global user.name "Your Name"

$Env:CHEF_LICENSE = "accept-no-persist"
$Env:HAB_LICENSE = "accept-no-persist"

Write-Output "--- Verifying commands"
Write-Output " * chef env"
chef env
If ($lastexitcode -ne 0) { Exit $lastexitcode }

Write-Output " * chef report"
chef report help
If ($lastexitcode -ne 0) { Exit $lastexitcode }

Write-Output " * hab help"
hab help
If ($lastexitcode -ne 0) { Exit $lastexitcode }

Write-Output " * chef-automate-collect -h"
chef exec chef-automate-collect -h
If ($lastexitcode -ne 0) { Exit $lastexitcode }

Write-Output "--- Run the verification suite"
C:/opscode/chef-workstation/embedded/bin/ruby.exe omnibus/verification/run.rb
If ($lastexitcode -ne 0) { Exit $lastexitcode }
