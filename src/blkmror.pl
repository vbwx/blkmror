# Black Mirror
# [Syncs directories and backs up deleted files.]
# Version 1.2.1
# Copyright (C) 2007, 2013 Bernhard Waldbrunner

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA


use File::Find;
use File::Copy;
use File::Copy::Recursive qw(dircopy dirmove);
use File::Spec::Functions;
use subs qw(die warn);


do {
	$more_args = 0;
	$src = shift or
		arg_error("Mandatory arguments are missing! (SRC & TARGET)");
	$src eq '?' and help();
	$src eq '!' and version();
	$src eq '--help' and help();
	$src eq '--version' and version();
	if ($src =~ /^-/) {
		$more_args = 1;
		$src =~ /v/ and $is_verbose  = 1;
		$src =~ /q/ and $is_quiet    = 1;
		$src =~ /b/ and $no_backup   = 1;
		$src =~ /h/ and $do_hidden   = 1;
		$src =~ /r/ and $no_readonly = 1;
		$src =~ /t/ and $do_temp     = 1;
		$src =~ /l/ and $no_log      = 1;
		$src =~ /p/ and $is_pretend  = 1;
		$src =~ /T/ and $do_tree     = 1;
		$src =~ /S/ and $is_strict   = 1;
		$src =~ /d/ and $do_dirs     = 1;
		$src =~ /a/ and $do_attribs  = 1;
		$src =~ /x/ and $no_xmode    = 1;
		$src =~ /C/ and $do_cleanup  = 1;
		$src =~ /^-[vqbhrtlpTSdaxC]+$/ or
			arg_error("Invalid switch handed over! ($src)");
	} else {
		$target = shift or
			arg_error("A mandatory argument is missing! (TARGET)");
	}
} while ($more_args);
($is_verbose && $is_quiet) and arg_error('Contradictory switches! (q & v)');
($is_quiet && $is_pretend) and arg_error('Contradictory switches! (q & p)');
unless ($is_quiet) {
	($do_attribs && $no_xmode) and print STDERR
		"Switch -a is ineffective when -x is active!\n";
	($do_tree && $is_pretend) and print STDERR
		"Switch -p is ineffective when -T is active!\n";
	($do_dirs && ($is_pretend || $do_tree)) and print STDERR
		"Switch -d is ineffective when -p or -T is active!\n";
	($do_attribs && $do_tree) and print STDERR
		"Switch -a is ineffective when -T is active!\n";
	($no_xmode && $do_tree) and print STDERR
		"Switch -x is ineffective when -T is active!\n";
	($do_cleanup && $do_tree) and print STDERR
		"Switch -C is ineffective when -T is active!\n";
	($do_cleanup && $is_pretend) and print STDERR
		"Note: Switch -C only pretends cleaning up when -p is active.\n";
}
$is_pretend ||= $do_tree;
$do_attribs ||= $no_xmode;

BEGIN
{
	if ($^O eq "MSWin32") {
		$is_Windows = 1;
		eval 'use Win32::File qw(GetAttributes SetAttributes HIDDEN)';
	} elsif ($^O eq "darwin") {
		$is_MacOSX = 1;
		eval 'use Unicode::Normalize qw(compose NFD)';
	}
}

if ($is_Windows) {
	$src =~ s!["\\/]+$!!; $src =~ s/^"//;
	$target =~ s!["\\/]+$!!; $target =~ s/^"//;
} else {
	$src =~ s!/+$!!;
	$target =~ s!/+$!!;
}
$src = File::Spec->rel2abs($src);
$src eq ".." and arg_error("Invalid source path!");
while ($src =~ /\/\.\.\/|\/\.\.$/) {
	$src =~ /.*?\/[^\/]+\/\.\./ or arg_error("Invalid source path!");
	$src =~ s!(.*?)/[^/]+/\.\.!\1!;
}
$target = File::Spec->rel2abs($target);
$target eq ".." and arg_error("Invalid target path!");
while ($target =~ /\/\.\.\/|\/\.\.$/) {
	$target =~ /.*?\/[^\/]+\/\.\./ or arg_error("Invalid target path!");
	$target =~ s!(.*?)/[^/]+/\.\.!\1!;
}

-e $src or die "Source directory doesn't exist";
-d $src or die "Source is no directory";
(-e $target && !-d $target) and die "Target is no directory";
-e $target or mkdir canonpath($target) or die "Can't create target directory";

$Hidden = '.'; $src = catfile($src, ''); $target = catfile($target, '');
$Size = $Added = $Synced = $Unlinked = $Archived = $Backup = $Entries = 0;
$Cleanup = $Removed = 0;
print "This would be done:\n" if ($is_pretend && !$do_tree);
$| = 1 unless ($do_tree || $is_quiet);

if (-f catfile($src, '.BM_Tree') && !$do_tree
   && !-f catfile($target, '.BM_Tree')) {
	open(TREE, catfile($src, '.BM_Tree')) or
		die "Can't open <.BM_Tree>";
	while (<TREE>) {
		(/^\/[^\/]/ || /\t/) and die "<.BM_Tree> contains illegal characters";
		next if (/^\s*\/\// || /^\s*$/ || /^\.\.?\/?$/);
		s/\r?\n$//;
		if ($is_MacOSX) {
			$t = NFD($_); utf8::encode($t);
			push @Tree, $t;
		} else {
			push @Tree, $_;
		}
	}
	close TREE or warn "Can't close <.BM_Tree>";

	find( sub {
		unless ($_ eq '.' || $_ eq '..' || $File::Find::name =~ /^\Q$Hidden\E/
		       || $_ eq '.BM_Tree' || ($do_temp ? 0 : $_ =~ /\.te?mp$/i)
		       || ($no_log ? $_ =~ /\.log$/i : 0) || (-l $File::Find::name)
		       || ($no_readonly ? (!-W $File::Find::name) : 0)
		       || ($no_backup ? ($_ =~ /\w*~\w*$/ || $_ =~ /^~\$?/
		       || $_ =~ /\.bak$/i || $_ =~ /\.backup$/i) : 0)) {
			if ($is_Windows) {
				GetAttributes($File::Find::name, $Attr);
				(!$do_hidden && ($Attr & HIDDEN)) and
					$Hidden = $File::Find::name;
				$_ eq "Thumbs.db" and $Hidden = $File::Find::name;
			} else {
				(!$do_hidden && $_ =~ /^\./) and $Hidden = $File::Find::name;
			}
			if ($is_MacOSX) {
				$_ eq ".DS_Store" and $Hidden = $File::Find::name;
			}
			unless ($File::Find::name eq $Hidden) {
				$Path = canonpath($File::Find::name);
				$Path =~ s{^\Q$target\E}{}i;
				$Path =~ s{\\}{/}g if $is_Windows;
				$Path .= '/' if (-d $File::Find::name);
				$Path_src = catfile($src, $Path);
				$Path_target = catfile($target, $Path);
				$tree_contains = popElem(\@Tree, $Path);
				if (-e $Path_src && -M $Path_src < -M $Path_target
				   && $tree_contains) {
					if (-f $Path_target || -f $Path_src) {
						$Synced++;
						$Size += -s $Path_src;
						if ($is_verbose) {
							print "* $Path\n";
						} elsif (!$is_quiet && !$is_pretend) {
							print '.';
						}
						unless ($is_pretend) {
							($atime, $mtime) = (stat($Path_src))[8,9];
							if (-d $Path_target) {
								remtree($Path_target);
							} else {
								unlink $Path_target or
									die "Can't delete <$Path_target>";
							}
							if (-d $Path_src) {
								mkdir $Path_target or die
									"Can't create directory <$Path_target>";
								utime $atime, $mtime, $Path_target or warn
									"Can't update time stamps of <$Path>";
							} elsif (-f $Path_src) {
								copy($Path_src, $Path_target) or
									warn "Can't copy <$Path>";
								utime $atime, $mtime, $Path_target or warn
									"Can't update time stamps of <$Path>";
							}
						}
						if ($do_attribs && -e $Path_target && !$do_tree) {
							$mode = (stat $Path_src)[2] & 0777;
							$mode &= 0666 if ($no_xmode && !-d $Path_target);
							chmod $mode, $Path_target;
							if ($is_Windows) {
								GetAttributes($Path_src, $Attr);
								SetAttributes($Path_target, $Attr);
							} elsif ($is_MacOSX) {
								setfinfo(getfinfo($Path_src), $Path_target);
							}
						}
					}
				} elsif (!-e $Path_src && (!$is_strict
				        || -M $Path_target <= -M catfile($src, ".BM_Tree"))) {
					$Archived++;
					$Backup += -s $Path_target;
					if ($tree_contains) {
						print "\n<$Path_src> doesn't exist!" unless $is_quiet;
						unless ($is_pretend) {
							($atime, $mtime) = (stat($Path_target))[8,9];
							if (-d $Path_target) {
								dircopy($Path_target, $Path_src) or warn
									"Can't copy directory <$Path>";
								utime $atime, $mtime, $Path_src or warn
									"Can't update time stamps of <$Path>";
							} elsif (-f $Path_target) {
								copy($Path_target, $Path_src) or warn
									"Can't copy <$Path>";
								utime $atime, $mtime, $Path_src or warn
									"Can't update time stamps of <$Path>";
							}
						}
						if ($do_attribs && -e $Path_target && !$do_tree
						   && -e $Path_src) {
							$mode = (stat $Path_target)[2] & 0777;
							$mode &= 0666 if ($no_xmode && !-d $Path_src);
							chmod $mode, $Path_src;
							if ($is_Windows) {
								GetAttributes($Path_target, $Attr);
								SetAttributes($Path_src, $Attr);
							} elsif ($is_MacOSX) {
								setfinfo(getfinfo($Path_target), $Path_src);
							}
						}
					} else {
						if ($do_attribs && -e $Path_target && !$do_tree) {
							$mode = (stat $Path_target)[2] & 0777;
							if ($is_Windows) {
								GetAttributes($Path_target, $Attr);
							} elsif ($is_MacOSX) {
								$finfo = getfinfo($Path_target);
							}
						}
						if (-M $Path_target <= -M catfile($src, ".BM_Tree")
						   && !$is_quiet) {
							print(($is_verbose ? "" : "\n") . "<$Path> will be"
								. " backed up.\n");
						}
						unless ($is_pretend) {
							($atime, $mtime) = (stat($Path_target))[8,9];
							if (-d $Path_target) {
								dirmove($Path_target, $Path_src) or warn
									"Can't move directory <$Path>";
								utime $atime, $mtime, $Path_src or warn
									"Can't update time stamps of <$Path>";
							} elsif (-f $Path_target) {
								move($Path_target, $Path_src) or warn
									"Can't move <$Path>";
								utime $atime, $mtime, $Path_src or warn
									"Can't update time stamps of <$Path>";
							}
						}
						if ($do_attribs && -e $Path_src && !$do_tree) {
							$mode &= 0666 if ($no_xmode && !-d $Path_src);
							if ($is_Windows) {
								SetAttributes($Path_src, $Attr);
							} elsif ($is_MacOSX) {
								setfinfo($finfo, $Path_src);
							}
						}
					}
				} elsif (!$tree_contains) {
					$Unlinked++;
					if ($is_verbose) {
						print "- $Path\n";
					} elsif (!$is_quiet && !$is_pretend) {
						print '.';
					}
					unless ($is_pretend) {
						if (-d $Path_target) {
							remtree($Path_target);
						} else {
							unlink $Path_target or
								die "Can't delete <$Path_target>";
						}
					}
				}
				$Cleanup += del_archived($Path_src) if $do_cleanup;
			}
		}
	}, $target);
	$Hidden = '.';
	for $Path (@Tree) {
		next if (!defined($Path) || $Path eq '' || $Path =~ /\.BM_Tree$/
		        || (-l catfile($src, canonpath($Path)))
		        || $Path =~ /^\Q$Hidden\E/ || ($do_temp ? 0 :
		        $Path =~ /\.te?mp$/i) || ($no_log ? $Path =~ /\.log$/i : 0) ||
		        ($no_backup ? ($Path =~ /\w*~\w*$/ ||
		        $Path =~ /[\\\/]~\$?[^\/\\]+$/ || $Path =~ /^~\$?[^\/\\]+/
		        || $Path =~ /\.bak$/i || $Path =~ /\.backup$/i) : 0));
		if ($is_Windows) {
			GetAttributes(catfile($src, canonpath($Path)), $Attr);
			(!$do_hidden && ($Attr & HIDDEN)) and $Hidden = $Path;
			$Path =~ /Thumbs\.db$/ and $Hidden = $Path;
		} else {
			(!$do_hidden && ($Path =~ /^\./ || $Path =~ /[\/]\.[^\/]+$/))
				and $Hidden = $Path;
		}
		if ($is_MacOSX) {
			$Path =~ /\.DS_Store$/ and $Hidden = $Path;
		}
		unless ($Path eq $Hidden) {
			$Path_src = catfile($src, $Path);
			$Path_target = catfile($target, $Path);
			if (-e $Path_src) {
				if (-e $Path_target && -M $Path_src < -M $Path_target) {
					if (-f $Path_target || -f $Path_src) {
						$Synced++;
						$Size += -s $Path_src;
						if ($is_verbose) {
							print "* $Path\n";
						} elsif (!$is_quiet && !$is_pretend) {
							print '.';
						}
						unless ($is_pretend) {
							($atime, $mtime) = (stat($Path_src))[8,9];
							if (-d $Path_target) {
								remtree($Path_target);
							} else {
								unlink $Path_target or
									die "Can't delete <$Path_target>";
							}
							if (-d $Path_src) {
								mkdir $Path_target or die
									"Can't create directory <$Path_target>";
								utime $atime, $mtime, $Path_target or warn
									"Can't update time stamps of <$Path>";
							} elsif (-f $Path_src) {
								copy($Path_src, $Path_target) or
									warn "Can't copy <$Path>";
								utime $atime, $mtime, $Path_target or warn
									"Can't update time stamps of <$Path>";
							}
						}
					}
				} elsif (!-e $Path_target) {
					if (-d $Path_src) {
						$Added++;
						if ($is_verbose) {
							print "+ $Path\n";
						} elsif (!$is_quiet && !$is_pretend) {
							print '.';
						}
						unless ($is_pretend) {
							($atime, $mtime) = (stat($Path_src))[8,9];
							mkdir $Path_target or
								die "Can't create directory <$Path_target>";
							utime $atime, $mtime, $Path_target or warn
								"Can't update time stamps of <$Path>";
						}
					} elsif (-f $Path_src) {
						$Added++;
						$Size += -s $Path_src;
						if ($is_verbose) {
							print "+ $Path\n";
						} elsif (!$is_quiet && !$is_pretend) {
							print '.';
						}
						unless ($is_pretend) {
							($atime, $mtime) = (stat($Path_src))[8,9];
							copy($Path_src, $Path_target) or
								warn "Can't copy <$Path>";
							utime $atime, $mtime, $Path_target or warn
								"Can't update time stamps of <$Path>";
						}
					}
				}
				if ($do_attribs && -e $Path_target && !$do_tree) {
					$mode = (stat $Path_src)[2] & 0777;
					$mode &= 0666 if ($no_xmode && !-d $Path_target);
					chmod $mode, $Path_target;
					if ($is_Windows) {
						GetAttributes($Path_src, $Attr);
						SetAttributes($Path_target, $Attr);
					} elsif ($is_MacOSX) {
						setfinfo(getfinfo($Path_src), $Path_target);
					}
				}
				$Cleanup += del_archived($Path_src) if $do_cleanup;
			} else {
				print STDERR "\n<$Path_src> doesn't exist!";
			}
		}
	}
} else {
	unless ($is_pretend && !$do_tree) {
		if (-f catfile($target, '.BM_Tree')) {
			unlink catfile($target, '.BM_Tree') or
				die "Can't delete <.BM_Tree>";
		}
		if ($is_MacOSX) {
			open(TREE, '>'.catfile($target, '._BM_Tree')) or
				die "Can't write to <._BM_Tree>";
		} else {
			open(TREE, '>'.catfile($target, '.BM_Tree')) or
				die "Can't write to <.BM_Tree>";
		}
	}

	find( sub {
		unless ($_ eq '.' || $_ eq '..' || $File::Find::name =~ /^\Q$Hidden\E/
		       || ($do_temp ? 0 : $_ =~ /\.te?mp$/i)
		       || ($no_log ? $_ =~ /\.log$/i : 0) || (-l $File::Find::name)
		       || ($no_readonly ? (!-W $File::Find::name) : 0)
		       || ($no_backup ? ($_ =~ /\w*~\w*$/ || $_ =~ /^~\$?/
		       || $_ =~ /\.bak$/i || $_ =~ /\.backup$/i) : 0)) {
			if ($is_Windows) {
				GetAttributes($File::Find::name, $Attr);
				(!$do_hidden && ($Attr & HIDDEN)) and
					$Hidden = $File::Find::name;
				$_ eq "Thumbs.db" and $Hidden = $File::Find::name;
			} else {
				(!$do_hidden && $_ =~ /^\./) and $Hidden = $File::Find::name;
			}
			if ($is_MacOSX) {
				$_ eq ".DS_Store" and $Hidden = $File::Find::name;
			}
			unless ($File::Find::name eq $Hidden) {
				$Path = canonpath($File::Find::name);
				$Path =~ s{^\Q$src\E}{}i;
				$Path =~ s{\\}{/}g if $is_Windows;
				$Path .= '/' if (-d $File::Find::name);
				print TREE $Path . "\n" unless ($is_pretend && !$do_tree);
				$Entries++;
				return if $do_tree;
				$Path_src = catfile($src, $Path);
				$Path_target = catfile($target, $Path);
				if (-e $Path_target && -M $Path_src < -M $Path_target) {
					if (-f $Path_target || -f $Path_src) {
						$Synced++;
						if (-d $Path_src || -d $Path_target) {
							$Backup += -s $Path_target;
							$Archived++;
						}
						$Size += -s $Path_src;
						if ($is_verbose) {
							print "* $Path\n";
						} elsif (!$is_quiet && !$is_pretend) {
							print '.';
						}
						unless ($is_pretend) {
							($atime, $mtime) = (stat($Path_src))[8,9];
							if (-d $Path_target || -d $Path_src) {
								archive($Path_target);
							} else {
								unlink $Path_target or
									die "Can't delete <$Path_target>";
							}
							if (-d $Path_src) {
								mkdir $Path_target or die
									"Can't create directory <$Path_target>";
								utime $atime, $mtime, $Path_target or warn
									"Can't update time stamps of <$Path>";
							} elsif (-f $Path_src) {
								copy($Path_src, $Path_target) or
									warn "Can't copy <$Path>";
								utime $atime, $mtime, $Path_target or warn
									"Can't update time stamps of <$Path>";
							}
						}
					}
				} elsif (!-e $Path_target) {
					if (-d $Path_src) {
						$Added++;
						if ($is_verbose) {
							print "+ $Path\n";
						} elsif (!$is_quiet && !$is_pretend) {
							print '.';
						}
						unless ($is_pretend) {
							($atime, $mtime) = (stat($Path_src))[8,9];
							mkdir $Path_target or
								die "Can't create directory <$Path_target>";
							utime $atime, $mtime, $Path_target or warn
								"Can't update time stamps of <$Path>";
						}
					} elsif (-f $Path_src) {
						$Added++;
						$Size += -s $Path_src;
						if ($is_verbose) {
							print "+ $Path\n";
						} elsif (!$is_quiet && !$is_pretend) {
							print '.';
						}
						unless ($is_pretend) {
							($atime, $mtime) = (stat($Path_src))[8,9];
							copy($Path_src, $Path_target) or
								warn "Can't copy <$Path>";
							utime $atime, $mtime, $Path_target or warn
								"Can't update time stamps of <$Path>";
						}
					}
				}
				if ($do_attribs && -e $Path_src && -e $Path_target
				   && !$do_tree) {
					$mode = (stat $Path_src)[2] & 0777;
					$mode &= 0666 if ($no_xmode && !-d $Path_target);
					chmod $mode, $Path_target;
					if ($is_Windows) {
						GetAttributes($Path_src, $Attr);
						SetAttributes($Path_target, $Attr);
					} elsif ($is_MacOSX) {
						setfinfo(getfinfo($Path_src), $Path_target);
					}
				}
				$Cleanup += del_archived($Path_target) if $do_cleanup;
			}
		}
	}, $src);

	if ($is_MacOSX) {
		unless ($is_pretend && !$do_tree) {
			close TREE or warn "Can't close <._BM_Tree>";
			open(TREE8, "<:utf8", catfile($target, "._BM_Tree")) or
				die "Can't read <._BM_Tree>";
			open(TREE, ">:encoding(latin1)", catfile($target, ".BM_Tree")) or
				die "Can't write to <.BM_Tree>";
			while (<TREE8>) {
				print TREE compose($_);
			}
			close TREE8 or warn "Can't close <._BM_Tree>";
			unlink catfile($target, '._BM_Tree') or
				die "Can't delete <._BM_Tree>";
		}
	}
	print "\n.BM_Tree file updated." unless $is_pretend;
	SetAttributes(catfile($target, '.BM_Tree'), HIDDEN) if $is_Windows;
	unless ($is_pretend && !$do_tree) {
		close TREE or warn "Can't close <.BM_Tree>";
	}
}

unless ($is_quiet) {
	if ($do_tree) {
		print "$Entries lines written to <".catfile($target, ".BM_Tree").">.";
	} else {
		for $x (qw(Size Backup Cleanup)) {
			${'_'.$x} = "B";
			if ($$x >= 1024) {
				$$x /= 1024; ${'_'.$x} = "KB";
			}
			if ($$x >= 1024) {
				$$x /= 1024; ${'_'.$x} = "MB";
			}
			if ($$x >= 1024) {
				$$x /= 1024; ${'_'.$x} = "GB";
			}
		}
		print "\n$Added file(s) added, $Unlinked file(s) removed, "
			. "$Synced file(s) synchronized;\n";
		printf "%.1f $_Size copied, $Archived file(s) backed up "
			. "(%.1f $_Backup)", $Size, $Backup;
		printf("\n$Removed archived file(s) deleted (%.1f $_Cleanup)",
			$Cleanup) if $do_cleanup;
		if ($is_pretend) {
			print "\n\n--> File attributes/modes have been synchronized."
				if $do_attribs;
			print " (X-modes removed.)" if $no_xmode;
		}
	}
	print "\n";
}


sub help
{
	print <<'END';
usage:
blkmror [SWITCHES] SRC_DIR TARGET_DIR
    If TARGET_DIR contains a file called <.BM_Tree>, Black Mirror copies all
    new or changed files found in SRC_DIR to TARGET_DIR and updates the global
    index file <.BM_Tree>.
    If SRC_DIR contains the global index file, Black Mirror will copy, delete
    or update all files necessary in order to adjust TARGET_DIR to SRC_DIR.
    In this case both directories are being synchronized. Also, files found in
    TARGET_DIR that haven't existed before in SRC_DIR will be archived to the
    directory with <.BM_Tree> (i.e., the backup device).
    If no directory contains <.BM_Tree>, it will be created in TARGET_DIR.
    If both directories contain an index file, they will just be kept in sync,
    without deleting any files or directories.
blkmror !
    Displays version info.

SWITCHES:
    -q  Quiet operation.
    -v  Verbose. Also print out detailed error reports.
    -h  Include hidden files and directories.
    -t  Include temporary files.
    -r  Exclude read-only files and directories.
    -b  Exclude backup files.
    -l  Exclude log files.
    -p  Pretend: Don't copy or delete anything.
    -T  Only create the .BM_Tree file, don't copy or delete anything.
    -S  Strict: Only forward backups (from SRC_DIR to TARGET_DIR), if at all.
    -d  No special treatment for extensions in directory names ("packages").
    -a  Sync attributes/modes of files too. (Even when -p is active.)
    -x  Like -a, but removes x-modes from files. (Even when -p is active.)
    -C  Clean up backup directory. (Remove archived files.)
END
	exit(0);
}


sub version
{
	print <<'END';
Black Mirror: Version 1.2
Copyright (C) 2007 Bernhard Waldbrunner

   Black Mirror comes with ABSOLUTELY NO WARRANTY.
   This is free software, and you are welcome to redistribute it
   under certain conditions; go to http://www.gnu.org/licenses/gpl-2.0.html
   for details.

See LICENSE.txt for more information.
END
	exit(0);
}


sub die
{
	my $message = shift || "Unknown fatal error";
	print STDERR ($is_verbose || $is_quiet ? "" : "\n") . $message . "!"
		. ($is_verbose ? " (".$!.")" : "") . "\n";
	exit(255);
}


sub warn
{
	my $message = shift || "Unknown error";
	print STDERR ($is_verbose || $is_quiet ? "" : "\n") . $message . "!"
		. ($is_verbose ? " (".$!.")" : "") . "\n";
}


## arg_error($message)
## message: Explanation why the arguments are erroneous
sub arg_error
{
	my $message = shift || "Unknown argument error.";
	print STDERR $message . "\nType 'blkmror ?' to get help.\n";
	exit(1);
}


## remtree($dir)
## dir: Directory to remove recursively
sub remtree
{
	my $root = canonpath(shift);
	local *ROOT;

	opendir ROOT, $root or die "Can't open directory <$root>";
	while ($_ = readdir ROOT) {
		next if /^\.\.?$/;
		my $path = catfile($root, $_);
		if (-d $path) {
			remtree($path);
		} else {
			unlink $path or die "Can't delete <$path>";
		}
	}
	closedir ROOT or warn "Can't close directory <$root>";
	rmdir $root or warn "Can't remove directory <$root>";
}


## archive($file)
## file: Path of file or directory to rename (archive)
sub archive
{
	my $file = canonpath(shift);

	my $i = 1;
	if ($do_dirs && -d $file || !($file =~ /.+\.\w+$/)) {
		while (-e ($file."~$i")) {
			$i++;
		}
		rename($file, $file."~$i") or die "Can't rename <$file/>";
	} else {
		my($f, $ext) = ($file =~ /(.+)\.(\w+)$/);
		while (-e ($f."~$i.".$ext)) {
			$i++;
		}
		rename($file, $f."~$i.".$ext) or die "Can't rename <$file>";
	}
}


## popElem(\@array, $elem)
## RETURNS 1 if the element has been found (and deleted)
## array: reference to an array of elements where the element should be seeked
## elem: element to be seeked and deleted if present
sub popElem
{
	$array = shift or die '&popElem: \@array missing';
	$elem = shift or die '&popElem: $elem missing';

	for ($i = 0; $i < scalar @$array; $i++) {
		next unless defined($array->[$i]);
		if ($array->[$i] eq $elem) {
			delete $array->[$i] or die "&popElem: Can't delete element $i";
			return 1;
		}
	}
	return 0;
}


## is_archived($file)
## RETURNS 1 if the file has been archived
## file: File (without backup number) to be checked
sub is_archived
{
	my $file = canonpath(shift);

	if ($do_dirs && -d $file || !($file =~ /.+\.\w+$/)) {
		return 1 if -e ($file."~1");
	} else {
		my($f, $ext) = ($file =~ /(.+)\.(\w+)$/);
		return 1 if -e ($f."~1.".$ext);
	}
	return 0;
}


## del_archived($file)
## RETURNS size (in bytes) of found and deleted archived files
## file: File (without backup number) whose archived versions are to be deleted
sub del_archived
{
	my $file = canonpath(shift);
	my $size = 0;

	return 0 unless -e $file;
	if ($do_dirs && -d $file || !($file =~ /.+\.\w+$/)) {
		@ary = glob($file."~*");
	} else {
		my($f, $ext) = ($file =~ /(.+)\.(\w+)$/);
		@ary = glob($f."~*.".$ext);
	}
	for $f (@ary) {
		if ($f =~ /~\d+/) {
			$Removed++; $size += -s $f;
			unless ($is_pretend) {
				if (-d $f) {
					remtree($f);
				} else {
					unlink $f or warn "Can't delete <$f>";
				}
			}
		}
	}
	return $size;
}
