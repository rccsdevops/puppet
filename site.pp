# /etc/puppetlabs/code/environments/production/manifests/site.pp

# Default for everyone else
node default {
  file { '/tmp/hello-puppet.txt':
    ensure  => file,
    content => "Hello from Puppet! Managed at ${facts['networking']['fqdn']}\n",
  }
}

# Specific agent (replace with your real certname!)
node 'ip-10-0-1-247.ec2.internal' {
  package { 'nginx':
    ensure => installed,
  }

  service { 'nginx':
    ensure => running,
    enable => true,
  }

  file { '/var/www/html/index.html':
    ensure  => file,
    content => "<html>\n<head><title>Puppet Demo</title></head>\n<body>\n<h1>Hello from Puppet!</h1>\n<p>This page is managed by Puppet on ${facts['networking']['fqdn']}.</p>\n</body>\n</html>\n",
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    require => Package['nginx'],
  }

}
