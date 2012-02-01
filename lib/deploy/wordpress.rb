require 'erb'
Capistrano::Configuration.instance.load do
  default_run_options[:pty] = true

  #allow deploys w/o having git installed locally
  set(:real_revision) do
    output = ""
    invoke_command("git ls-remote #{repository} #{branch} | cut -f 1", :once => true) do |ch, stream, data|
      case stream
      when :out
        if data =~ /\(yes\/no\)\?/ # first time connecting via ssh, add to known_hosts?
          ch.send_data "yes\n"
        elsif data =~ /Warning/
        elsif data =~ /yes/
          #
        else
          output << data
        end
      when :err then warn "[err :: #{ch[:server]}] #{data}"
      end
    end
    output.gsub(/\\/, '').chomp
  end

  #no need for log and pids directory
  set :shared_children, %w(system)

  namespace :deploy do
    desc "Override deploy restart to not do anything"
    task :restart do
      #
    end

    task :finalize_update, :except => { :no_release => true } do
      run "chmod -R g+w #{latest_release}"

      run <<-CMD
        mkdir -p #{latest_release}/finalized &&
        cp -rv   #{shared_path}/wordpress/*     #{latest_release}/finalized/ &&
        cp -rv   #{shared_path}/wp-config.php   #{latest_release}/finalized/wp-config.php &&
        rm -rf   #{latest_release}/finalized/wp-content &&
        mkdir    #{latest_release}/finalized/wp-content &&
        cp -rv   #{latest_release}/themes       #{latest_release}/finalized/wp-content/ &&
        cp -rv   #{latest_release}/plugins      #{latest_release}/finalized/wp-content/
      CMD
    end

    task :symlink, :except => { :no_release => true } do
      on_rollback do
        if previous_release
          run "rm -f #{current_path}; ln -s #{previous_release}/finalized #{current_path}; true"
        else
          logger.important "no previous release to rollback to, rollback of symlink skipped"
        end
      end

      run <<-CMD
        rm -f #{current_path} && 
        ln -s #{shared_path}/uploads #{latest_release}/finalized/wp-content/uploads &&
        ln -s #{latest_release}/finalized #{current_path}
      CMD
    end
  end

  namespace :setup do

    desc "Setup a new server for use with wordpress-capistrano. This runs as root."
    task :server do
      #set :user, 'root'
      #util.users
      #mysql.password
      #util.generate_ssh_keys
    end

    desc "Setup this server for a new wordpress site."
    task :wordpress do
      deploy.setup
      db.setup
      wp.setup
    end

  end

  namespace :util do

    task :users do
      set :user, 'root'
      run "groupadd -f wheel"
      run "useradd -g wheel wordpress || echo"
      reset_password
      set :password_user, 'wordpress'
      reset_password
    end

    task :passwords do
      set(:wordpress_db_name, fetch(:wordpress_db_name, Capistrano::CLI.ui.ask("Wordpress Database Name:"))) unless exists?(:wordpress_db_name)
      set(:wordpress_db_user, fetch(:wordpress_db_user, Capistrano::CLI.ui.ask("Wordpress Database User:"))) unless exists?(:wordpress_db_user)
      set(:wordpress_db_password, fetch(:wordpress_db_password, Capistrano::CLI.ui.ask("Wordpress Database Password:"))) unless exists?(:wordpress_db_password)
    end

    task :generate_ssh_keys do
      run "#{try_sudo} mkdir -p /home/wordpress/.ssh"
      run "#{try_sudo} chmod 700 /home/wordpress/.ssh"
      run "if [ -f /home/wordpress/.ssh/id_rsa ]; then echo 'SSH key already exists'; else #{try_sudo} ssh-keygen -q -f /home/wordpress/.ssh/id_rsa -N ''; fi"
      pubkey = capture("cat /home/wordpress/.ssh/id_rsa.pub")
      puts "Below is the SSH public key for your server."
      puts "Please add this key to your account on GitHub."
      puts ""
      puts pubkey
      puts ""
    end

    task :reset_password do
      password_user = fetch(:password_user, 'root')
      puts "Changing password for user #{password_user}"
      password_set = false
      while !password_set do
        password = Capistrano::CLI.ui.ask "New UNIX password:"
        password_confirmation = Capistrano::CLI.ui.ask "Retype new UNIX password:"
        if password != ''
          if password == password_confirmation
            run "echo \"#{ password }\" | sudo passwd --stdin #{password_user}"
            password_set = true
          else
            puts "Passwords did not match"
          end
        else
          puts "Password cannot be blank"
        end
      end
    end

  end

  namespace :apache do
    desc "Creates a vhost configuration file and restarts apache"
    task :configure do
      aliases = []
      aliases << "www.#{domain}"
      aliases.concat fetch(:server_aliases, [])
      set :server_aliases_array, aliases

      file = File.join(File.dirname(__FILE__), "..", "vhost.conf.erb")
      template = File.read(file)
      buffer = ERB.new(template).result(binding)

      put buffer, "#{shared_path}/#{application}.conf"
      sudo "mv #{shared_path}/#{application}.conf /etc/httpd/conf.d/"
      sudo "/etc/init.d/httpd restart"
    end
  end

  namespace :db do
    
    task :setup do
      run "mkdir -p #{shared_path}/dumps"
    end

    desc "Sets the MySQL root password, assuming there is none"
    task :password do
      puts "Setting MySQL Password"
      password_set = false
      while !password_set do
        password = Capistrano::CLI.ui.ask "New MySQL password:"
        password_confirmation = Capistrano::CLI.ui.ask "Retype new MySQL password:"
        if password == password_confirmation
          run "mysqladmin -uroot password #{password}"
          password_set = true
        else
          puts "Passwords did not match"
        end
      end
    end

    desc "Creates MySQL database and user for wordpress"
    task :create_databases do
      util.passwords
      set(:mysql_root_password, fetch(:mysql_root_password, Capistrano::CLI.password_prompt("MySQL root password:"))) unless exists?(:mysql_root_password)
      run "mysqladmin -uroot -p#{mysql_root_password} --default-character-set=utf8 create #{wordpress_db_name}"
      run "echo 'GRANT ALL PRIVILEGES ON #{wordpress_db_name}.* to \"#{wordpress_db_user}\"@\"localhost\" IDENTIFIED BY \"#{wordpress_db_password}\"; FLUSH PRIVILEGES;' | mysql -uroot -p#{mysql_root_password}"
    end

    desc "Import a MySQL database"
    task :import_database do
      file = File.read(ENV["FILE"])
      util.passwords
      run "rm #{shared_path}/import.sql || true"
      put file, "#{shared_path}/import.sql"
      run "mysql -u#{wordpress_db_user} -p#{wordpress_db_password} #{wordpress_db_name} < #{shared_path}/import.sql"
    end
    
    task :fix_home_site_url do
	    replace_home_and_siturl = "UPDATE wp_options SET option_value = \"http://#{domain}\" WHERE option_name = \"home\" OR option_name = \"siteurl\";"
      run "mysql -u #{wordpress_db_user} --password=#{wordpress_db_password} #{wordpress_db_name} -e '#{replace_home_and_siturl}'"
    end
    
    desc "Dump database."
	  task :dump do
	    filename = "#{Time.now.strftime '%Y%m%dT%H%M%S'}.sql"
	    run "mysqldump -u #{wordpress_db_user} --password=#{wordpress_db_password} #{wordpress_db_name} > #{shared_path}/dumps/#{filename}"
	    run "ln -nfs #{shared_path}/dumps/#{filename} #{shared_path}/dumps/latest.sql"
    end
    
    namespace :local do
      
      desc "Dumps local database and uploads it to the server."
  	  task :upload do
  	    dump = `#{local_mysql}dump -u #{local_mysql_user} --password=#{local_mysql_password}  #{local_mysql_database}`
  	    filename = "#{Time.now.strftime '%Y%m%dT%H%M%S'}.sql"
  	    put dump, "#{shared_path}/dumps/#{filename}"
  	    run "ln -nfs #{shared_path}/dumps/#{filename} #{shared_path}/dumps/latest.sql"
      end
    end
    
    desc "Loads latest.sql from shared/db/dumps"
    task :import_latest_dump do
      run "mysql -u #{wordpress_db_user} --password=#{wordpress_db_password} #{wordpress_db_name} < #{shared_path}/dumps/latest.sql"
    end
    
  end

  namespace :wp do
    
    task :setup do
      run <<-CMD
        mkdir -p #{shared_path}/uploads
      CMD
      
      wp.config
      wp.checkout
    end
    
    desc "Checks out a copy of wordpress to a shared location."
    task :checkout do
      run "rm -rf #{shared_path}/wordpress || true"
      run "git clone #{wordpress_git_url} #{shared_path}/wordpress -b #{wordpress_git_branch}"
    end

    desc "Sets up wp-config.php"
    task :config do
      #util.passwords
      file = File.join(File.dirname(__FILE__), "..", "wp-config.php.erb")
      template = File.read(file)
      buffer = ERB.new(template).result(binding)

      put buffer, "#{shared_path}/wp-config.php"
      puts "wp-config.php uploaded. Please run cap:deploy to activate these changes."
    end
    
    desc "Upload local uploads to shared uploads"
    task :upload_uploads do
      upload "uploads", "#{shared_path}", via: :scp, recursive: true
      puts "Uploaded files. Please run cap:deploy to symlink these files."
    end
    
  end

end