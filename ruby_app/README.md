Chef Cookbook for a Sinatra Web App
====================================

Configures and deploys a plain ol' ruby app.  Confirmed to work with Amazon OpsWorks.


Recipes
------------------------------------
* `ruby_app::configure` -- one time, makes all the deploy folders
* `ruby_app::deploy` -- uses scm to update the codebase, bundle installs, and restarts the server


Required Databag
------------------------------------

```json
{
  "service_realm": "production",
  "web_application_type": "ruby_app",
  "opsworks_bundler": { "version": "1.3.5", "manage_package": true },
  "opsworks_rubygems": { "version": "2.0.3" },
  "opsworks": {
    "rack_stack": { "name": "nginx_unicorn", "recipe": "unicorn::rack", "service": "unicorn" },
    "ruby_stack": "ruby"
  },
  "deploy": {
    "etl_app": {
      "application_type": "ruby_app",
      "rack_env": "production",
      "environment": {
        "rack_env": "production"
      },
      "env": {
        "MY_ENV_X": "..."
      }
    }
  }
}
```

Dependencies
------------------------------------
* `deploy`: https://github.com/aws/opsworks-cookbooks/tree/master/deploy

###### Optional Dependencies

* `nginx`: https://github.com/aws/opsworks-cookbooks/tree/master/nginx
* `unicorn::rack`: https://github.com/crowdmob/opsworks-cookbooks/tree/master/unicorn


