# nginx.pp

class nginx ( $passenger_enabled = 'true', $passenger_friendly_error_pages = 'off', $passenger_max_pool_size = 30, $passenger_min_instances = 1, $passenger_version = '3.0.7', $php_support = 'absent', $port = 80, $ruby_install_path = '/usr/local', $worker_connections = 1024, $worker_processes = 10, $logrotate = 'present' ) {

	package { 'libcurl4-openssl-dev': ensure => 'installed' }
	package { 'passenger':
		provider	=> gem, 
		ensure 		=> $passenger_version,
		require 	=> Package['libcurl4-openssl-dev'],
	}

	# Get rid off Apache2
	exec { "remove-apache2":
		command	=> "/usr/bin/apt-get -y remove --purge apache2-mpm-worker apache2-threaded-dev apache2-utils apache2.2-common ruby1.8 && /usr/bin/apt-get -y autoremove",
		onlyif	=> "/usr/bin/test -e /usr/sbin/apache2ctl"
	}

	# Install Nginx
	exec { "passenger-install-nginx-module":
		command => "$ruby_install_path/bin/passenger-install-nginx-module --auto --auto-download --prefix=/opt/nginx", 
		creates => "/opt/nginx/sbin/nginx", 
		require => [Package['passenger', 'libcurl4-openssl-dev'], Exec["remove-apache2"]]
	} 
	
	# Vhost dir	
	file { "/opt/nginx/sites-enabled":
		ensure	=> directory,
		require => Exec["passenger-install-nginx-module"],
	}
	# Additional conf
	file { "/opt/nginx/conf/extras":
		ensure	=> directory,
		require => Exec["passenger-install-nginx-module"],
	}

	# Default nginx.conf
	file { "/opt/nginx/conf/nginx.conf":
		content	=> template("nginx/nginx.conf.erb"),
		require => Exec["passenger-install-nginx-module"],
		notify 	=> Service["nginx"]
	}
	
	# Logrotation
	file { "/opt/nginx/logs/archive":
		ensure  => directory,
		require => Exec["passenger-install-nginx-module"]
	}
	
	case $logrotate {
		present: {
			file { "/etc/logrotate.d/nginx":
				ensure	=> present,
				source  => "puppet:///modules/nginx/logrotate",
				require => Exec["passenger-install-nginx-module"]
			}
		}
		absent: {
			file { "/etc/logrotate.d/nginx":
				ensure	=> absent
			}
		}
	}

	# PHP Support
	case $php_support {
		'present': {
			package { "php5-cgi": ensure => installed }
			package { "php5": ensure => installed }
			file { "/etc/init.d/php-fcgi":
				ensure  => present,
				mode	=> 755,
				source  => "puppet:///modules/nginx/php-fcgi",
				require => Package["php5-cgi", "php5"],
				notify  => Service["nginx"]
			}
			file { "/etc/php5/cgi/php.ini":
				ensure  => present,
				content => template("nginx/php.ini.erb"),
				require => Package["php5-cgi", "php5"],
				notify  => Service["nginx"]
			}
			service { "php-fcgi":
				ensure  => running,
				status  => "/bin/pidof /usr/bin/php-cgi",
				require	=> File["/etc/init.d/php-fcgi"]	
			}
		}
		'absent': {
			file { "/etc/init.d/php-fcgi":
				ensure  => absent,
				notify  => Service["nginx"]
			}
		}
	}

	# Service config
   	service { "nginx":
      		ensure 	=> running,
		start	=> "/opt/nginx/sbin/nginx",
		stop	=> "/opt/nginx/sbin/nginx -s stop",
		status	=> "ps -p `cat /opt/nginx/logs/nginx.pid`",
		require	=> Exec["passenger-install-nginx-module"],
	}

}
