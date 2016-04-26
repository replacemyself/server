define percona::user (
  $user        = undef,
  $password    = undef,
  $host        = 'localhost',
  $ensure      = 'present',
  $root_username,
  $root_password
) {

  ## Determine the default user/host to use derived from the resource name.
  case $name {
    /^(\w+)@([^ ]+)\/(\w+)$/: {
      $default_user = $1
      $default_host = $2
      $default_database = $3
    }
    /^(\w+)@([^ ]+)$/: {
      $default_user = $1
      $default_host = $2
      $default_database = undef
    }
    default: {
      $default_user = undef
      $default_host = undef
      $default_database = undef
    }
  }

  $_user = $user ? {
    undef   => $default_user,
    default => $user,
  }

  $_host = $host ? {
    'localhost' => $default_host,
    default     => $host,
  }

  exec { "create-user-${name}":
    command => "mysql -u${root_username} -p${root_password} -e \"CREATE USER '${_user}'@'${_host}' IDENTIFIED BY PASSWORD '${password}';\"",
    path    => '/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin',
    require => [
        Percona::Adminpass["${root_username}"],
        Service[$::percona::service_name]
    ],
  }

}
