# chocolatey_server - Host your own Chocolatey package repository
#
# @author Rob Reynolds and puppet-chocolatey_server contributors
#
# @example Default - install the server
#   include chocolatey_server
#
# @example Use a different port
#   class {'chocolatey_server':
#     port => '8080',
#   }
#
# @example Use an internal source for installing the `chocolatey.server` package
#   class {'chocolatey_server':
#     server_package_source => 'http://someinternal/nuget/odatafeed',
#   }
#
# @example Use a local file source for the `chocolatey.server` package
#   class {'chocolatey_server':
#     server_package_source => 'c:/folder/containing/packages',
#   }
#
# @param [String] port The port for the server website. Defaults to '80'.
# @param [String] server_package_source The chocolatey source that contains
#   the `chocolatey.server` package. Defaults to
#   'https://chocolatey.org/api/v2/'.
# @param [String] server_install_location The location to that the chocolatey
#   server will be installed.  This is can be used if you are controlling
#   the location that chocolatey packages are being installed via some other
#   means. e.g. environment variable ChocolateyBinRoot.  Defaults to
#   'C:\tools\chocolatey.server'
class chocolatey_server (
  $port = $::chocolatey_server::params::service_port,
  $server_package_source = $::chocolatey_server::params::server_package_source,
  $server_install_location = $::chocolatey_server::params::server_install_location,
  $certificate_hash = $::chocolatey_server::params::cert_hash,
) inherits ::chocolatey_server::params {
  require ::chocolatey

  $_chocolatey_server_location      = $server_install_location
  $_chocolatey_server_app_pool_name = 'chocolateyserver'
  $_chocolatey_server_app_port      = $port
  $_chocolatey_certificate          = $certificate_hash
  $_server_package_url              = $server_package_source

  $_is_windows_2008 = $::kernelmajversion ? {
    '6.1'   => true,
    default => false,
  }

  $_web_asp_net = $_is_windows_2008 ? {
    true    => 'Web-Asp-Net',
    default => 'Web-Asp-Net45'
  }

  # package install
  package {'chocolatey.server':
    ensure   => installed,
    provider => chocolatey,
    source   => $_server_package_url,
  }

  # add windows features
  dsc_windowsfeature { 'IIS':
    dsc_ensure => 'present',
    dsc_name   => 'Web-Server',
  }
  # add windows management tools
  -> dsc_windowsfeature { 'Mgmt-Console':
    dsc_ensure => 'present',
    dsc_name   => 'Web-Mgmt-Console',
  }
  # install aspnet package
  -> dsc_windowsfeature { $_web_asp_net:
    dsc_ensure => 'present',
    dsc_name   => $_web_asp_net,
  }
  if $::kernelmajversion > '6.1' {
    dsc_windowsfeature { 'Web-AppInit':
      dsc_ensure => present,
      dsc_name   => 'Web-AppInit',
    }
  }
  # install iis scripting tools
  dsc_windowsfeature { 'IIS-Scripting-Tools':
    dsc_ensure => present,
    dsc_name   => 'Web-Scripting-Tools',
  }
  # stop the default website
  dsc_xwebsite { 'Default Web Site':
    dsc_ensure          => 'absent',
    dsc_name            => 'Default Web Site',
    dsc_applicationpool => 'DefaultAppPool',
  }

  # create application in iis
  dsc_xwebapppool { chocolateyserver:
    dsc_ensure                => 'present',
    dsc_name                  => 'chocolateyserver',
    dsc_managedruntimeversion => 'v4.0',
    dsc_enable32bitapponwin64 => true,
    dsc_startmode             => 'AlwaysRunning',
    dsc_identitytype          => 'ApplicationPoolIdentity',
    dsc_state                 => 'Started',
  }

  # create both http and https bindings.  certificate hash required for https binding.
  -> dsc_xwebsite { 'chocolateyserver':
    dsc_ensure          => 'present',
    dsc_name            => 'chocolateyserver',
    dsc_physicalpath    => $_chocolatey_server_location,
    dsc_applicationpool => $_chocolatey_server_app_pool_name,
    dsc_preloadenabled  => true,
    dsc_bindinginfo     =>  [
      {
        ipaddress => '*',
        port      => '80',
        protocol  => 'http',
        hostname  => $_chocolatey_hostname,
      },
      {
        ipaddress             => '*',
        port                  => '443',
        protocol              => 'https',
        certificatethumbprint => $_chocolatey_certificate,
        certificatestorename  => 'MY',
        sslflags              => 0,
      },
    ],
    require             => Package['chocolatey.server'],
  }

  # lock down web directory
  -> acl { $_chocolatey_server_location:
    purge                      => true,
    inherit_parent_permissions => false,
    permissions                => [
      { identity => 'Administrators',
        rights   => ['full'] },
      { identity => 'IIS_IUSRS',
        rights   => ['read'] },
      { identity => 'IUSR',
        rights   => ['read'] },
      { identity => "IIS APPPOOL\\${_chocolatey_server_app_pool_name}",
        rights   => ['read'] }
    ],
    require                    => Package['chocolatey.server'],
  }
  -> acl { "${_chocolatey_server_location}/App_Data":
    permissions => [
      { identity => "IIS APPPOOL\\${_chocolatey_server_app_pool_name}",
        rights   => ['modify'] },
      { identity => 'IIS_IUSRS',
        rights   => ['modify'] }
    ],
    require     => Package['chocolatey.server'],
  }
  # technically you may only need IIS_IUSRS but I have not tested this yet.
}
