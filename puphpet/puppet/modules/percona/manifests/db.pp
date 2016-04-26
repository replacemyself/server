define percona::db (
  $ensure      = 'present',
  $charset     = 'utf8',
  $root_username,
  $root_password
) {
  exec { "create-database-${name}":
    command => "mysql -u${root_username} -p${root_password} -e \"CREATE DATABASE ${name};\"",
    path    => '/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin',
    require => [
        Percona::Adminpass["${root_username}"],
        Service[$::percona::service_name]
    ],
  }
}
