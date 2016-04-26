define percona::grants (
  $ensure         = 'present',
  $privileges     = 'all',
  $table          = undef,
  $user           = undef,
  $host           = 'localhost',
  $root_username,
  $root_password
) {

  $priv = join($privileges, ',')

  case $user {
    /^(\w+)@([^ ]+)\/(\w+)$/: {
      $default_user = $1
      $default_host = $2
    }
    /^(\w+)@([^ ]+)$/: {
      $default_user = $1
      $default_host = $2
    }
    default: {
      $default_user = undef
      $default_host = undef
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

  exec { "grant-user-${name}":
    command => "mysql -u${root_username} -p${root_password} -e \"GRANT ${priv} ON ${table} TO '${_user}'@'${_host}'; FLUSH PRIVILEGES;\"",
    path    => '/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin',
    require => [
        Percona::Adminpass["${root_username}"],
        Service[$::percona::service_name]
    ],
  }
}
