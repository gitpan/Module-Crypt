#! perl -w

use warnings;
use strict;

use File::Spec ();
use Test;
BEGIN { plan tests => 4 }

use ExtUtils::testlib;
use Module::Crypt;
ok eval "require Module::Crypt";

BEGIN {
	chdir 't';
	use lib 'output';
}

our $source_file = File::Spec->catfile('Foo.pm');
our $install_base = File::Spec->catfile('output');
	
	{
		local *FH;
		open FH, "> $source_file" or die "Can't create $source_file: $!";
		print FH <<'EOF';
package Foo;
use strict;
use warnings;
our $VERSION = 1.00;
sub multiply {
	return $_[0] * $_[1];
}
1;
EOF
		close FH;
	}
	
	
	ok CryptModule(
		name => 'Foo',
		file => $source_file,
		install_base => $install_base
	);
	
	unlink $source_file;

	ok eval "require Foo";
	ok (Foo::multiply(2,3) == 6);
	
sub END {
	system("rm", "-rf", $install_base);
}

chdir '..';

__END__
