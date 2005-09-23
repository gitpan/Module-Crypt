# ===========================================================================
# Module::Crypt - version 0.03 - 23 Sep 2005
# 
# Encrypt your Perl code and compile it into XS
# 
# Author: Alessandro Ranellucci <aar@cpan.org>
# Copyright (c) 2005 - All Rights Reserved.
# 
# This is EXPERIMENTAL code. Use it AT YOUR OWN RISK.
# See below for documentation.
# 

package Module::Crypt;

use strict;
use warnings;
our $VERSION = 0.03;

use Carp qw[croak];
use File::Basename qw[basename];
use File::Path ();
use Module::Build;

require Exporter;
our @ISA = qw[Exporter Module::Build];
our @EXPORT = qw[CryptModule];

use XSLoader;
XSLoader::load 'Module::Crypt', $VERSION;

our @delete_lib_dirs;

sub CryptModule {
	my %Params = @_;
	
	# check module name
	croak("Module name is required") unless $Params{name};
	
	# check module file
	$Params{file} ||= "$Params{name}.pm";
	croak("Please use the 'file' option to locate the .pm module") unless -e $Params{file};
	$Params{file} = File::Spec->rel2abs($Params{file});
	
	# let's copy the module to lib directory so that
	# Module::Build can read version
	my $lib_dir = File::Spec->rel2abs('lib');
	my @module_path = split(/::/, $Params{name});
	pop @module_path;
	File::Path::mkpath(join "/", $lib_dir, @module_path);
	push(@delete_lib_dirs, $lib_dir);
	system("cp", $Params{file}, join("/", $lib_dir, @module_path));
	
	# let's make sure install_base exists
	$Params{install_base} ||= 'output';
	$Params{install_base} = File::Spec->rel2abs($Params{install_base});
	File::Path::mkpath($Params{install_base});
	croak("Please check that $Params{install_base} exists") unless -d $Params{install_base};
	
	# initialize the builder
	my $build = __PACKAGE__->new(
		module_name => $Params{name},
		install_path => {
			lib => $Params{install_base},
			arch => $Params{install_base}
		},
		pod_files => {}
	);
	
	# set version
	$Params{version} ||= $build->version_from_file($Params{file});
	croak('$VERSION must be specified in your module') unless $Params{version};
	
	# write XS code
	_write_c(%Params);
	
	# do the build
	$build->dispatch('code');
	push(@delete_lib_dirs, File::Spec->rel2abs('blib'));
	
	# let's install the auto directory
	system("mv", File::Spec->rel2abs('blib/arch/auto'), $Params{install_base});
	
	# let's install the module
	File::Path::mkpath(join "/", $Params{install_base}, @module_path);
	my $modpath = "$Params{name}.pm";
	$modpath =~ s|::|/|g;
	system(
		"mv", 
		File::Spec->rel2abs("blib/lib/$modpath"), 
		File::Spec->rel2abs( File::Spec->catfile($Params{install_base}, @module_path) )
	);
	
	_cleanup();
	return 1
}

sub END {
	_cleanup();
}

sub _cleanup {
	system("rm", "-rf", $_) while ($_ = shift @delete_lib_dirs);
}

sub _write_c {
	my %Params = @_;
	
	my $basename = basename($Params{file}, '.pm');
	
	# get source script
	open(SRC, "<$Params{file}");
	my @lines = <SRC>;
	close SRC;
	
	open(XS, ">lib/$basename.xs");
	
	# encrypt things
	print XS wr(join "", @lines);
	print XS <<"EOF"

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <EXTERN.h>
#include <perl.h>
#include <stdlib.h>

/**
 * 'Alleged RC4' Source Code picked up from the news.
 * From: allen\@gateway.grumman.com (John L. Allen)
 * Newsgroups: comp.lang.c
 * Subject: Shrink this C code for fame and fun
 * Date: 21 May 1996 10:49:37 -0400
 */

static unsigned char stte[256], indx, jndx, kndx;

/*
 * Reset arc4 stte. 
 */
void stte_0(void)
{
	indx = jndx = kndx = 0;
	do {
		stte[indx] = indx;
	} while (++indx);
}

/*
 * Set key. Can be used more than once. 
 */
void key(void * str, int len)
{
	unsigned char tmp, * ptr = (unsigned char *)str;
	while (len > 0) {
		do {
			tmp = stte[indx];
			kndx += tmp;
			kndx += ptr[(int)indx % len];
			stte[indx] = stte[kndx];
			stte[kndx] = tmp;
		} while (++indx);
		ptr += 256;
		len -= 256;
	}
}

/*
 * Crypt data. 
 */
void arc4(void * str, int len)
{
	unsigned char tmp, * ptr = (unsigned char *)str;
	while (len > 0) {
		indx++;
		tmp = stte[indx];
		jndx += tmp;
		stte[indx] = stte[jndx];
		stte[jndx] = tmp;
		tmp += stte[indx];
		*ptr ^= stte[tmp];
		ptr++;
		len--;
	}
}

MODULE = $Params{name}		PACKAGE = $Params{name}

BOOT:
	stte_0();
	 key(pswd, pswd_z);
	arc4(text, text_z);
	eval_pv(text, G_SCALAR);

EOF
	;
	close XS;
	
	open(PM, ">lib/$basename.pm");
	print PM <<"EOF"
package $Params{name};

use strict;
use warnings;

our \$VERSION = $Params{version};

use XSLoader;
XSLoader::load __PACKAGE__, \$VERSION;

1;

EOF
	;
	close PM;
}

1;

__END__

=head1 NAME

Module::Crypt - Encrypt your Perl code and compile it into XS

=head1 SYNOPSIS

 use Module::Crypt;
 
 CryptModule(
    name => 'Foo::Bar',
    file => 'Bar.pm',
    install_base => '/path/to/lib'
 );


=head1 ABSTRACT

Module::Crypt encrypts your pure-Perl modules and then compiles them
into a XS module. It lets you distribute binary versions without
disclosing code, although please note that we should better call this
an obfuscation, as Perl is still internally working with your original
code. While this isn't 100% safe, it makes code retrival much harder than
any other known Perl obfuscation method.

=head1 PUBLIC FUNCTIONS

=over 4

=item C<CryptModule>

This function does the actual encryption and compilation. It is supposed
to be called from a Makefile-like script that you'll create inside your development
directory. The 5 lines you see in the SYNAPSIS above are sufficient to build 
(and rebuild) the module.

=over 8

=item name

This must contain the name of the module in package form (such as Foo::Bar). 
It's required.

=item file

This is not required in most cases, as Module::Crypt locates the 
module file using the module name, but it's safer to specify it expecially
when you have a multilevel module (that is Foo::Bar instead of, say, simply Foo).

=item install_base

(Optional) This parameter contains the destination of the compiled modules. If not
specified, it defaults to a directory named "output" inside the current working directory.

=back

=back

=head1 BUGS

=over 4

=item

Module::Crypt is currently only able to encrypt one module/file for each Perl run.

=item

Exporter may not work (actually this is untested).

=item

There could be some malloc() errors when encrypting long scripts. It should be very 
easy to fix this (the cause is bad way to calculate allocation needs).

=item

The build backend is based on Module::Build, which is not very flexible and requires
some bad workarounds to produce working modules. Module::Build should borrow C/XS related
subroutines from its code, subclass or maybe switch to ExtUtils::CBuilder.

=back

=head1 AVAILABILITY

Latest versions can be downloaded from CPAN. You are very welcome to write mail 
to the author (aar@cpan.org) with your contributions, comments, suggestions, 
bug reports or complaints.

=head1 AUTHOR

Alessandro Ranellucci E<lt>aar@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2005 Alessandro Ranellucci. All Rights Reserved.
Module::Crypt is free software, you may redistribute it and/or modify it under 
the same terms as Perl itself.

=head1 DISCLAIMER

This is highly experimental code. Use it AT YOUR OWN RISK. 
This software is provided by the copyright holders and contributors ``as
is'' and any express or implied warranties, including, but not limited to,
the implied warranties of merchantability and fitness for a particular
purpose are disclaimed. In no event shall the regents or contributors be
liable for any direct, indirect, incidental, special, exemplary, or
consequential damages (including, but not limited to, procurement of
substitute goods or services; loss of use, data, or profits; or business
interruption) however caused and on any theory of liability, whether in
contract, strict liability, or tort (including negligence or otherwise)
arising in any way out of the use of this software, even if advised of the
possibility of such damage.

=cut