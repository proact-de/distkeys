# Distkeys

Distkeys distributes a list of SSH public keys to a list of servers. It
reaches servers behind a firewall as well.

Furthermore it executes a command or a script on a list of servers.

Distkeys is a ruby script which requires:

* Ruby ;)
* Net::SSH v2, debian package ruby-net-ssh
  (Squeeze and older: libnet-ssh2-ruby)
* Net::SSH::Gateway, debian package ruby-net-ssh-gateway
  (Squeeze and older: libnet-ssh-gateway-ruby)
* Net::SFTP v2, debian package ruby-net-sftp
  (Squeeze and older: libnet-sftp2-ruby)
* Termios, debian package ruby-termios
  (Squeeze and older: libtermios-ruby)
* SCP

Distkeys can also use SFTP, when you remove the occurences of
":via => :scp". This is not configurable via option yet.

Read more in our blog (in german):

[Distkeys als Open Source](http://blog.teamix.de/2013/10/06/distkeys-als-open-source/)


## VCS

Distkeys is hosted at:

https://www.teamix.org/projects/distkeys

https://github.com/teamix/distkeys

The git repository is prepared to handle debian package builds via
git-buildpackage. It has the following branches:

* master: This is were changes to the Debian packages go.
* upstream: This is were upstream changes go.
* pristine-tar: This would be for release tarballs if any.


## SSH Configuration

Using the `-F` command line option, you may specify an alternative
per-user SSH configuration file which will be used instead of the default
`~/.ssh/config` (see `ssh(1)`'s `-F` command line option for details).

For example, given the following `~/.ssh/distkeys.config`:

	Host *
		ForwardAgent yes
		Compression yes
		StrictHostKeyChecking no
		IdentityFile ~/.ssh/tmx_rsa

Then, `distkeys -F ~/.ssh/distkeys.config -h <hostlist> <action>`
will cause Distkeys to enable agent forwarding and compression, disable
strict host key checking and using `~/.ssh/tmx_rsa` as SSH identity file.

See the `ssh_config(5)` manpage for details about available configuration
options.


## Known Issues

### does not take UTF-8 more byte character length into account when writing data to a file

Net:SFTP truncates writes with more byte UTF-8 characters.
This happens with Net::SFTP 3.0.0.

Do not use more byte characters in the description for an SSH key until this issue is fixed.

[https://github.com/net-ssh/net-sftp/issues/133](does not take UTF-8 more byte character length into account when writing data to a file #133)

### Uninitialized contant Net::SFTP::Session:StringIO in Net::STFP v2 < 2.0.5

There is an error in Net::SFTP v2 prior to 2.0.5 which needs to be added
manually:

If you get:

	/usr/[...]/lib/net/sftp/session.rb:123:in `download!': uninitialized constant Net::SFTP::Session::StringIO (NameError)

add

	require 'stringio'

to the top of the session.rb file mentioned in the exception message.

For further information about this error, see:

[ruby net-sftp uninitialized constant](http://toblog.bryans.org/2010/08/19/ruby-net-sftp-uninitialized-constant)

