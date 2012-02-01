require 'rubygems'
require 'railsless-deploy'
require 'capistrano/ext/multistage'
require "highline/import"

load 'deploy'

# the domain name for the server you'll be running wordpress on
set :domain, "localhost"

# other domain names your app will respond to (dev.blog.com, etc)
#set :server_aliases, []

# the stages that are available 
set :stages, %w(staging production)
set :default_stage, "staging"

# the name of this wordpress project
set :application, "example"

# your repo
set :github_username, ""
set :github_repository, ""
set :repository,  "git://github.com/#{github_username}/${github_repository}.git"
set :scm, :git
set :branch, "master"
set :deploy_via, :remote_cache
set :scm_verbose, true

require File.join(File.dirname(__FILE__), 'lib', 'deploy', 'wordpress')

# Customizations
#==============

# if you need to use a different version of wordpress, specify that here
set :wordpress_git_url, "git://github.com/markjaquith/WordPress.git"
set :wordpress_git_branch, "3.3-branch"

# these are randomized on `cap setup:wordpress`
# set :wordpress_auth_key, Digest::SHA1.hexdigest(rand.to_s)
# set :wordpress_secure_auth_key, Digest::SHA1.hexdigest(rand.to_s)
# set :wordpress_logged_in_key, Digest::SHA1.hexdigest(rand.to_s)
# set :wordpress_nonce_key, Digest::SHA1.hexdigest(rand.to_s)

# these are used for dumping local databases
set :local_mysql, "/usr/bin/mysql"
set :local_mysql_database, ""
set :local_mysql_user, ""
set :local_mysql_password, ""
