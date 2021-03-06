maintainer        "CaseNEX, LLC"
maintainer_email  "mprosper@casenex.com"
license           "Apache 2.0"
description       "SCM checkout, bundle install, and restart plain ol ruby applications (relies on aws-opsworks/deploy)."
depends           "deploy"
recipe						"ruby_app::setup", "Set up a vanilla ruby app"
recipe            "ruby_app::configure", "Configure a vanilla ruby app"
recipe            "ruby_app::deploy", "Deploy a vanilla ruby app" 