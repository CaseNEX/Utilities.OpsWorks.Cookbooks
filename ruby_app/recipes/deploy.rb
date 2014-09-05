node[:deploy].each do |application, _|

	Chef::Log.info "[recipe ruby_app::deploy] node[:deploy][application][:deploy_to] == '#{node[:deploy][application][:deploy_to]}'"

	directory "#{node[:deploy][application][:deploy_to]}" do
		group       node[:deploy][application][:group]
		owner       node[:deploy][application][:user]
		mode        "0775"
		action      :create
		recursive   true
	end

	if node[:deploy][application][:scm]
		ensure_scm_package_installed(node[:deploy][application][:scm][:scm_type])

		if node[:deploy][application][:scm][:scm_type].to_s == 'git'
			prepare_git_checkouts(
					:user =>    node[:deploy][application][:user],
					:group =>   node[:deploy][application][:group],
					:home =>    node[:deploy][application][:home],
					:ssh_key => node[:deploy][application][:scm][:ssh_key]
			)

		elsif node[:deploy][application][:scm][:scm_type].to_s == 'svn'
			prepare_svn_checkouts(
					:user =>        node[:deploy][application][:user],
					:group =>       node[:deploy][application][:group],
					:home =>        node[:deploy][application][:home],
					:deploy =>      node[:deploy],
					:application => application
			)

		elsif node[:deploy][application][:scm][:scm_type].to_s == 'archive'
			repository = prepare_archive_checkouts(node[:deploy][application][:scm])
			node[:deploy][application][:scm] = {
					:scm_type =>    'git',
					:repository =>  repository
			}

		elsif node[:deploy][application][:scm][:scm_type].to_s == 's3'
			repository = prepare_s3_checkouts(node[:deploy][application][:scm])
			node[:deploy][application][:scm] = {
					:scm_type =>    'git',
					:repository =>  repository
			}
		end
	end

	Chef::Log.debug("Checking out source code of application #{application} with type #{node[:deploy][application][:application_type]}")

	directory "#{node[:deploy][application][:deploy_to]}/shared/cached-copy" do
		recursive   true
		action      :delete
		only_if     { node[:deploy][application][:delete_cached_copy] }
	end

	ruby_block "change HOME to #{node[:deploy][application][:home]} for source checkout" do
		block do
			ENV['HOME'] = "#{node[:deploy][application][:home]}"
		end
	end

	Chef::Log.debug("[ruby_app] Running 'deploy' operation and will restart and sleep")

	# setup deployment & checkout
	if node[:deploy][application][:scm]
		deploy node[:deploy][application][:deploy_to] do
			repository              node[:deploy][application][:scm][:repository]
			user                    node[:deploy][application][:user]
			revision                node[:deploy][application][:scm][:revision]
			migrate                 node[:deploy][application][:migrate]
			migration_command       node[:deploy][application][:migrate_command]
			environment             node[:deploy][application][:environment]
			symlink_before_migrate( node[:deploy][application][:symlink_before_migrate] )
			action                  node[:deploy][application][:action]

			# This is buggy with this version of chef, so we'll duplicate a little and manually call restart below (L156)
			# if node[:sinatra][application][:restart_command]
			#   restart_command       "echo 'sinatra restart' && sleep #{node[:deploy][application][:sleep_before_restart]} && #{node[:sinatra][application][:restart_command]}"
			# end

			case node[:deploy][application][:scm][:scm_type].to_s
				when 'git'
					scm_provider          :git
					enable_submodules     node[:deploy][application][:enable_submodules]
					shallow_clone         node[:deploy][application][:shallow_clone]
				when 'svn'
					scm_provider          :subversion
					svn_username          node[:deploy][application][:scm][:user]
					svn_password          node[:deploy][application][:scm][:password]
					svn_arguments         "--no-auth-cache --non-interactive --trust-server-cert"
					svn_info_args         "--no-auth-cache --non-interactive --trust-server-cert"
				else
					raise "unsupported SCM type #{node[:deploy][application][:scm][:scm_type].inspect}"
			end

			before_symlink do
        if node[:deploy][application][:auto_bundle_on_deploy]
          Chef::Log.info("Gemfile detected. Running bundle install.")
          Chef::Log.info("sudo su deploy -c 'cd #{release_path} && #{node[:deploy][application][:bundle_command]} install --path #{node[:deploy][application][:home]}/.bundler/#{application} --without=#{node[:deploy][application][:ignore_bundler_groups].join(' ')}'")

          bash "bundle install #{application}" do
            cwd release_path
            code <<-EOH
              sudo #{node[:deploy][application][:bundle_command]} install
            EOH
            action :run
          end
        end

        if system("grep #{application} /etc/monit/monitrc")
          execute "Stopping app #{application}" do
            cwd       node[:deploy][application][:current_path]
            command   "#{node[:opsworks][:rack_stack][:bundle_command]} exec ruby #{node[:deploy][application][:current_path]}/bin/#{application}.rb stop"
            user      node[:deploy][application][:user]
            action    :run
          end
        else
          template "/etc/monit/monitrc" do
            source "monitrc.erb"
            cookbook "ruby_app"
            mode 0700
            owner "root"
            group "root"
          end

          execute "Restarting monit" do
            command   "sudo /etc/init.d/monit restart"
            action    :run
          end
        end

			end

			before_migrate do
				link_tempfiles_to_current_release
				# additionally run any user-provided callback file
				run_callback_from_file("#{release_path}/deploy/before_migrate.rb")
			end
		end
	end

	ruby_block "change HOME back to /root after source checkout" do
		block do
			ENV['HOME'] = "/root"
		end
	end

	template "/etc/logrotate.d/opsworks_app_#{application}" do
		backup    false
		source    "logrotate.erb"
		cookbook  'deploy'
		owner     "root"
		group     "root"
		mode      0644
		variables( :log_dirs => ["#{node[:deploy][application][:deploy_to]}/shared/log" ] )
  end


  bash "Checking for running instances of #{application}" do
    code <<-EOH
			SERVICE='bin/#{application}';
			STATUS=1;
			DELAY=5;
			SLEPT=0;
			echo 'Checking for running process'
			while [ "$STATUS" -eq "1" ]
			do
				if ps aux | grep -v grep | grep $SERVICE > /dev/null
				then
						if $SLEPT -lt 120
						then
							sleep $DELAY
							SLEPT+=$DELAY;
						else
							STATUS=0;
						fi
				else
					echo 'No process running, starting app'
					STATUS=0;
				fi
			done

    EOH
    action :run
  end



		execute "Starting app #{application}" do
			cwd       node[:deploy][application][:current_path]
			command   "#{node[:opsworks][:rack_stack][:bundle_command]} exec ruby #{node[:deploy][application][:current_path]}/bin/#{application}.rb start"
      user      node[:deploy][application][:user]
			action    :run
		end

end