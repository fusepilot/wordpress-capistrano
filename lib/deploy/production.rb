set :domain, "www.example.com"

role :web, "#{domain}"

# deploy location
set :deploy_to, "/var/www/#{domain}"

# unless set here, we prompt you for these three on `cap setup:wordpress`
set :wordpress_db_name, ""
set :wordpress_db_user, ""
set :wordpress_db_password, ""
set :wordpress_db_host, ""

# sets wordpress home and siteurl. you can also set :wordpress_home and :wordpress_siteurl separately instead.
set :wordpress_url, "http://#{domain}"

# these are randomized on `cap setup:wordpress`
set :wordpress_auth_key, Digest::SHA1.hexdigest(rand.to_s)
set :wordpress_secure_auth_key, Digest::SHA1.hexdigest(rand.to_s)
set :wordpress_logged_in_key, Digest::SHA1.hexdigest(rand.to_s)
set :wordpress_nonce_key, Digest::SHA1.hexdigest(rand.to_s)