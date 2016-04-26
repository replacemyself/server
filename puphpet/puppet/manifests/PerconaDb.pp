class puphpet_perconadb (
  $perconadb,
  $apache,
  $nginx,
  $php,
  $hhvm,
) {

  include puphpet::apache::params
  include puphpet::mysql::params
  include mysql::params

  if array_true($apache, 'install') or array_true($nginx, 'install') {
    $webserver_restart = true
  } else {
    $webserver_restart = false
  }

  $root_username = 'root'
  $version = to_string($perconadb['settings']['version'])

  $server_package = $puphpet::params::perconadb_package_server_name
  $client_package = $puphpet::params::perconadb_package_client_name

  if array_true($php, 'install') {
    $php_package = 'php'
  } elsif array_true($hhvm, 'install') {
    $php_package = 'hhvm'
  } else {
    $php_package = false
  }

  $root_password = array_true($perconadb['settings'], 'root_password') ? {
    true    => $perconadb['settings']['root_password'],
    default => $mysql::params::root_password
  }

  $percona_server = array_true($perconadb, 'install_server') ? {
    true    => true,
    default => true
  }

  $configuration = {
    'mysqld/max_connections' => 150,
    'mysqld/skip-name-resolve' => '',
    'mysqld/key_buffer_size' => '32M',
    'mysqld/ft_min_word_len' => 3,
    'mysqld/innodb_file_per_table' => 1,
    'mysqld/innodb_buffer_pool_size' => '1024M',
    'mysqld/innodb_file_format' => 'Barracuda',
    'mysqld/innodb_read_ahead_threshold' => 0,
    'mysqld/innodb_doublewrite' => 1,
    'mysqld/long_query_time' => 2,
    'mysqld/slow_query_log' => 1,
    'mysqld/slow_query_log_file' => '/var/log/mysql/mysql-slow.log',
    'mysqld/net_buffer_length' => '512K',
    'mysqld/read_buffer_size' => '1M',
    'mysqld/sort_buffer_size' => '1M',
    'mysqld/join_buffer_size' => '1M',
    'mysqld/performance_schema' => 'OFF',
    'mysqld/expire-logs-days' => 1
  }

  percona::mgmt_cnf { '/etc/.puppet.cnf':
    password => $root_password,
  }

  class { 'percona':
    server => $percona_server,
    percona_version => $version,
    configuration => $configuration,
    manage_repo => true,
  }

  percona::adminpass{ "${root_username}":
    password  => $root_password,
  }

  $override_options = deep_merge($mysql::params::default_options, {
    'mysqld' => {
      'tmpdir' => $mysql::params::tmpdir,
    }
  })

  $perconadb_user = $override_options['mysqld']['user']

  # Ensure the user exists
  if ! defined(User[$perconadb_user]) {
    user { $perconadb_user:
      ensure => present,
    }
  }

  # Ensure the group exists
  if ! defined(Group[$mysql::params::root_group]) {
    group { $mysql::params::root_group:
      ensure => present,
    }
  }

  # Ensure the data directory exists
  if ! defined(File[$mysql::params::datadir]) {
    file { $mysql::params::datadir:
      ensure => directory,
      group  => $mysql::params::root_group,
      before => Class['percona']
    }
  }

  $perconadb_pidfile = $override_options['mysqld']['pid-file']

  # Ensure PID file directory exists
  exec { 'Create pidfile parent directory':
    command => "mkdir -p $(dirname ${perconadb_pidfile})",
    unless  => "test -d $(dirname ${perconadb_pidfile})",
    before  => Class['percona'],
    require => [
      User[$perconadb_user],
      Group[$mysql::params::root_group]
    ],
  }
  -> exec { 'Set pidfile parent directory permissions':
    command => "chown \
      ${perconadb_user}:${mysql::params::root_group} \
      $(dirname ${perconadb_pidfile})",
  }

  $root_info = {
    root_username => $root_username,
    root_password => $root_password
  }

  Mysql_user <| |>
  -> Mysql_database <| |>
  -> Mysql_grant <| |>

  # config file could contain no users key
  $users = array_true($perconadb, 'users') ? {
    true    => $perconadb['users'],
    default => { }
  }

  each( $users ) |$key, $user| {
    # if no host passed with username, default to localhost
    if '@' in $user['name'] {
      $name = $user['name']
    } else {
      $name = "${user['name']}@localhost"
    }

    # force to_string to convert possible ints
    $password_hash = mysql_password(to_string($user['password']))

    $merged = delete(merge($user, {
      ensure   => 'present',
      password => $password_hash,
    }), ['name'])

    create_resources( percona::user, {
      "${name}" => $merged
    }, $root_info)
  }

  # config file could contain no databases key
  $databases = array_true($perconadb, 'databases') ? {
    true    => $perconadb['databases'],
    default => { }
  }

  each( $databases ) |$key, $database| {
    $name = $database['name']
    $sql  = $database['sql']

    $import_timeout = array_true($database, 'import_timeout') ? {
      true    => $database['import_timeout'],
      default => 300
    }

    $merged = delete(merge($database, {
      ensure => 'present',
    }), ['name', 'sql', 'import_timeout'])

    create_resources( percona::db, {
      "${name}" => $merged
    }, $root_info)

    if $sql != '' {
      # Run import only on initial database creation
      $touch_file = "/.puphpet-stuff/db-import-${name}"

      exec{ "${name}-import":
        command     => "mysql ${name} < ${sql} && touch ${touch_file}",
        creates     => $touch_file,
        logoutput   => true,
        environment => "HOME=${::root_home}",
        path        => '/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin',
        timeout     => $import_timeout,
        require     => Mysql_database[$name]
      }
    }
  }

  # config file could contain no grants key
  $grants = array_true($perconadb, 'grants') ? {
    true    => $perconadb['grants'],
    default => { }
  }

  each( $grants ) |$key, $grant| {
    # if no host passed with username, default to localhost
    if '@' in $grant['user'] {
      $user = $grant['user']
    } else {
      $user = "${grant['user']}@localhost"
    }

    $table = $grant['table']

    $name = "${user}/${table}"

    $options = array_true($grant, 'options') ? {
      true    => $grant['options'],
      default => ['GRANT']
    }

    $merged = merge($grant, {
      ensure  => 'present',
      'user' => $user,
    })

    create_resources( percona::grants, {
      "{$name}" => $merged
    }, $root_info)
  }

  if $php_package == 'php' {
    if $::osfamily == 'redhat' and $php['settings']['version'] == '53' {
      $php_module = 'mysql'
    } elsif $::lsbdistcodename == 'lucid' or $::lsbdistcodename == 'squeeze' {
      $php_module = 'mysql'
    } elsif $::osfamily == 'debian' and $php['settings']['version'] in ['7.0', '70'] {
      $php_module = 'mysql'
    } elsif $::operatingsystem == 'ubuntu' and $php['settings']['version'] in ['5.6', '56'] {
      $php_module = 'mysql'
    } else {
      $php_module = 'mysqlnd'
    }

    if ! defined(Puphpet::Php::Module[$php_module]) {
      puphpet::php::module { $php_module:
        service_autorestart => $webserver_restart,
      }
    }
  }

  if array_true($perconadb, 'adminer')
    and $php_package
    and ! defined(Class['puphpet::adminer'])
  {
    $apache_webroot = $puphpet::apache::params::default_vhost_dir
    $nginx_webroot  = $puphpet::params::nginx_webroot_location

    if array_true($apache, 'install') {
      $adminer_webroot = $apache_webroot
      Class['puphpet_apache']
      -> Class['puphpet::adminer']
    } elsif array_true($nginx, 'install') {
      $adminer_webroot = $nginx_webroot
      Class['puphpet_nginx']
      -> Class['puphpet::adminer']
    } else {
      fail( 'Adminer requires either Apache or Nginx to be installed.' )
    }

    class { 'puphpet::adminer':
      location => "${$adminer_webroot}/adminer",
      owner    => 'www-data'
    }
  }

}
