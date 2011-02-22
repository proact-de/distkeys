====== Multikeys 2 ======

Multikeys 2 distributes a list of SSH public keys to a list of servers. It reaches servers behind a firewall as well.

Furthermore it executes a command or a script on a list of servers.

Multikeys is a ruby script which requires:

- Ruby ;)
- Net::SSH v2, debian package libnet-ssh2-ruby
- Net::SSH::Gateway, debian package libnet-ssh-gateway-ruby
- Net::SFTP v2, debian package libnet-sftp2-ruby
- Termios, debian package libtermios-ruby


===== SSH Configuration =====

Using the `-F' command line option, you may specify an alternative per-user SSH configuration file which will be used instead of the default `~/.ssh/config' (see ssh(1)'s `-F' command line option for details).

For example, given the following `~/.ssh/multikeys.config':

  Host *
      ForwardAgent yes
      Compression yes
      StrictHostKeyChecking no
      IdentityFile ~/.ssh/tmx_rsa

Then, `multikeys.rb -F ~/.ssh/multikeys.config -h <hostlist> <action>' will cause multikeys to enable agent forwarding and compression, disable strict host key checking and using ~/.ssh/tmx_rsa as SSH identity file.

See the ssh_config(5) manpage for details about available configuration options.


===== Known Issues =====

There is an error in Net::SFTP v2 prior to 2.0.5 which needs to be added manually:

If you get:

/usr/[...]/lib/net/sftp/session.rb:123:in `download!': uninitialized constant Net::SFTP::Session::StringIO (NameError) 

add

require 'stringio'

to the top of the session.rb file mentioned in the exception message.

For further information about this error, see:

http://toblog.bryans.org/2010/08/19/ruby-net-sftp-uninitialized-constant

