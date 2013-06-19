package Vcdiff;

use strict;

use Symbol;
use Carp;

our $VERSION = '0.504';


## This variable indicates what backend should be used. It should
## be a package name such as "Vcdiff::Xdelta3".

our $backend;


## When new backends are added, this should be updated so that
## the new backend will be probed for when none are already loaded.

our @known_backends = qw(
  Vcdiff::Xdelta3
  Vcdiff::OpenVcdiff
);


## These packages should be skipped when looking for a backend
## because they are internal to this distribution and share the
## Vcdiff namespace. In hindsight it might have been a good idea
## to give the backends their own namespace such as Vcdiff::Backend.

my @internal_packages = qw (
  Test
);



sub diff {
  _load_backend();

  {
    no strict "refs";
    return qualify("diff", $backend)->(@_);
  }
}

sub patch {
  _load_backend();

  {
    no strict "refs";
    return qualify("patch", $backend)->(@_);
  }
}

sub which_backend {
  _load_backend();

  return $backend;
}

sub _load_backend {
  ## If a backend is set, make sure it is loaded:

  if (defined $backend) {
    eval "require $backend";
    croak $@ if $@;
    return;
  }

  ## If a backend has already been loaded but not set, set it:

  foreach my $k (keys %INC) {
    if ($k =~ m{^Vcdiff/([^.]+)}) {
      my $pm = $1;
      next if grep { $pm eq $_ } @internal_packages;
      $backend = "Vcdiff::$pm";
      return;
    }
  }

  ## Try to find a suitable backend then load and set it:

  foreach my $backend_candidate (@known_backends) {
    eval "require $backend_candidate";

    if (!$@) {
      $backend = $backend_candidate;
      return;
    }
  }

  croak "Unable to find any Vcdiff backend modules (see perldoc Vcdiff)";
}

1;



__END__


=head1 NAME

Vcdiff - diff and patch for binary data

=head1 SYNOPSIS

B<In order to use this module you must install one or more backend modules (see below)>

    use Vcdiff;

    my $delta = Vcdiff::diff($source, $target);

    my $target2 = Vcdiff::patch($source, $delta);

    ## $target2 eq $target



=head1 DESCRIPTION

Given source and target data, the C<Vcdiff::diff> function computes a "delta" that encodes the information needed to turn source into target. Anyone who has the source and delta can derive the target with the C<Vcdiff::patch> function.

The point of this module is that if the source and target inputs are related then delta can be small relative to target, meaning it may be more efficient to send delta updates to clients over the network instead of re-sending the whole target every time.

Even though source and target don't necessarily have to be binary data (regular data is fine too), the delta will contain binary data including NUL bytes so if your transport protocols don't support this you will have to encode or escape it in some way (ie Base64). Compressing the delta before you do this might be worthwhile depending on the size of your changes and the entropy of your data.

The delta format is described by L<RFC 3284|http://www.faqs.org/rfcs/rfc3284.html>, "The VCDIFF Generic Differencing and Compression Data Format".




=head1 BACKENDS

L<Vcdiff> is "the DBI" of VCDIFF implementations.

L<Vcdiff> doesn't itself implement delta compression. Instead, it provides a consistent interface to various open-source VCDIFF (RFC 3284) implementations. The implementation libraries it interfaces to are called "backends". You must install at least one backend in order to use L<Vcdiff>.

The currently supported backends are described below. See the POD documentation in the backend module distributions for more details on the pros and cons of each backend.

In order to choose which backend to use, L<Vcdiff> will first check to see if the C<$Vcdiff::backend> variable is populated. If so, it will attempt to load that backend. This variable can be used to force a particular backend:

    {
        local $Vcdiff::backend = 'Vcdiff::OpenVcdiff';
        $delta = Vcdiff::diff($source, $target);
    }

Otherwise, L<Vcdiff> will check to see if any backends have been loaded already in the following order: B<Xdelta3, OpenVcdiff>. If so, it will choose the first one it finds:

    use Vcdiff::Xdelta3;
    $delta = Vcdiff::diff($source, $target);

If it doesn't find any loaded backends, it will try to load them in the same order as above.

Finally, if no backends can be loaded, an exception is thrown.

The backend that will be used can be determined with C<Vcdiff::which_backend()>.



=head2 Dependency Recommendations

Unless you are relying on features supported only in a specific backend, it's recommended that code that uses L<Vcdiff> be backend-agnostic like this:

    use Vcdiff;
    print Vcdiff::diff("hello", "hello world");

Instead of:

    use Vcdiff::Xdelta3;
    print Vcdiff::Xdelta3::diff("hello", "hello world");

That way the selection of which backend to use is as dynamic as possible.

If you're writing a module that depends on L<Vcdiff>, pick a backend and add that backend's package (ie C<Vcdiff::Xdelta3>) to your module's dependency list. This way a (sophisticated) user can force a different backend at install-time if the one you chose doesn't work for whatever reason.

Even more importantly, writing backend-agnostic code allows users of your module to choose which backend to use by setting C<$Vcdiff::backend> (or localising as described above). Backend-agnostic code also permits the flexibility of using one backend for diffing and another for patching (by localising C<$Vcdiff::backend> for specific operations).



=head2 BACKEND: Xdelta3

The L<Vcdiff::Xdelta3> backend module bundles Joshua MacDonald's L<Xdelta3|http://xdelta.org/> library.


=head2 BACKEND: open-vcdiff

The L<Vcdiff::OpenVcdiff> backend module depends on L<Alien::OpenVcdiff> which configures, builds, and installs Google's L<open-vcdiff|http://code.google.com/p/open-vcdiff/> library.


=head2 Future Backends

Another possible candidate would be Kiem-Phong Vo's L<Vcodex|http://www2.research.att.com/~gsf/download/ref/vcodex/vcodex.html> utility which contains a vcdiff implementation.

A really cool project would be a pure-perl VCDIFF implementation that could be used in environments that are unable to compile XS modules.

In the future I plan to build a L<Vcdiff::DumbDiffer> module (name undecided) that will completely ignore the source and create a delta that embeds the entire target. Obviously this defeats the purpose of delta compression but will allow deltas to be generated really fast. This will be useful because protocols that frequently replace the entire content won't need a special case for this.







=head1 STREAMING API

The streaming API is sometimes more convenient than the in-memory API. It can also be more efficient since it uses less memory. Also, you can start processing output before Vcdiff has finished.

Sometimes you have to use the streaming API in order to handle files that are too large to fit into your virtual address space (though note some backends have size limitations apart from this).

In order to send output to a stream, a file handle should be passed in as the 3rd argument to C<diff> or C<patch>:

    Vcdiff::diff("hello", "hello world", \*STDOUT);

In order to fully take advantage of streaming, either or both of the source and target parameters can also be file handles instead of strings. Here is the full-streaming mode where all parameters are file handles:

    open(my $source_fh, '<', 'source.dat') || die $!;
    open(my $target_fh, '<', 'target.dat') || die $!;
    open(my $delta_fh, '>', 'delta.dat') || die $!;

    Vcdiff::diff($source_fh, $target_fh, $delta_fh);

Note that in all current backends if the source parameter is a file handle it must be backed by an C<lseek(2)>able and/or C<mmap(2)>able file descriptor (in other words, a real file, not a pipe or socket). Vcdiff will throw an exception if the source file handle is unsuitable.





=head1 MEMORY MAPPED INPUTS

If the source or target/delta data is in a file, an alternative to the streaming API is to map the files into memory with C<mmap(2)> and then pass the mappings in to C<diff>/C<patch> as strings.

Doing so is more efficient than the streaming API for large files because fewer system calls are made and a kernel-space to user-space copy is avoided. However, as mentioned above, files that are too large to fit in your virtual address must be diffed with the streaming API (this is only an issue when diffing multi-gigabyte files on 32 bit systems).

Here is an example using L<Sys::Mmap>:

    use Sys::Mmap;

    open(my $source_fh, '<', 'source.dat') || die $!;
    open(my $target_fh, '<', 'target.dat') || die $!;
    open(my $delta_fh, '>', 'delta.dat') || die $!;

    my ($source_str, $target_str);

    mmap($source_str, 0, PROT_READ, MAP_SHARED, $source_fh) || die $!;
    mmap($target_str, 0, PROT_READ, MAP_SHARED, $target_fh) || die $!;

    Vcdiff::diff($source_str, $target_str, $delta_fh);

    munmap($source_str);
    munmap($target_str);

Note that the L<Vcdiff::OpenVcdiff> module does this under the hood for source if it is a file handle.




=head1 TESTING

The L<Vcdiff> distribution includes a test suite that is shared by all the backends. Backends contain stub test files that invoke L<Vcdiff::Test> functions.

Each backend also bundles backend-specific tests that relate to exception handling.

=head2 $Vcdiff::Test::testcases

This is a reference to an array that contains testcases. Each testcase is an array of 3 values. The first is the source, the second the target, and the third a test description.

Every time a test-case is verified, source will be diffed with target, source will then be patched with the delta and the output compared with source.

The tests currently verify a few basic cases up to a megabyte or so in length. I'd like to go through the various backend test-suites and copy any interesting corner cases so they can be re-applied to all other backends.



=head2 Vcdiff::Test::streaming()

The L<Vcdiff::Test::streaming()> test is somewhat mis-named. It loops through all test-cases described above and for each of them it tests every streaming/in-memory API combination. You will see this in the test output like so:

    ok 1 - [SSM]
    ok 2 - [MSM]
    ok 3 - [SMM]
    ok 4 - [MMM]
    ok 5 - [SSS]
    ok 6 - [MSS]
    ok 7 - [SMS]
    ok 8 - [MMS]

The S/M indicators show which API combination is being used in the order of source, target/delta, and output arguments. For example, C<SMS> means source is streamed in from a file, the target/delta is in memory, and the output is being streamed to a file.

=head2 extra-tests/cross-compat.t

The point of this test is to verify that the deltas produced by each backend are compatible will all other backends. For each combination of backend, all the L<streaming()> tests above are run.

Note that currently no backend-specific extensions like checksums or interleaving are enabled.

This test isn't run by default because it needs to have all backends installed.




=head1 SEE ALSO

L<Vcdiff github repo|https://github.com/hoytech/Vcdiff>

L<RFC 3284|http://www.faqs.org/rfcs/rfc3284.html>, "The VCDIFF Generic Differencing and Compression Data Format"


=head1 AUTHOR

Doug Hoyte, C<< <doug@hcsw.org> >>


=head1 COPYRIGHT & LICENSE

Copyright 2013 Doug Hoyte.

This module is licensed under the same terms as perl itself.

=cut