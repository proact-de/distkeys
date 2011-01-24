====== Multikeys 2 ======

Multikeys 2 distributes a list of SSH public keys to a list of servers. It reaches servers behind a firewall as well.

Furthermore it executes a command or a script on a list of servers.

Multikeys is a ruby script which requires:

- Ruby ;)
- Net::SSH v2, debian package libnet-ssh2-ruby
- Net::SSH::Gateway, debian package libnet-ssh-gateway-ruby
- Net::SFTP v2, debian package libnet-sftp2-ruby


===== Known Issues =====

There is an error in Net::SFTP v2 prior to 2.0.5 which needs to be added manualy:

If you get:

/usr/[...]/lib/net/sftp/session.rb:123:in `download!': uninitialized constant Net::SFTP::Session::StringIO (NameError) 

add

require 'stringio'

to the top of the session.rb file mentioned in the exception message.

See here for further information about this error:

http://toblog.bryans.org/2010/08/19/ruby-net-sftp-uninitialized-constant

