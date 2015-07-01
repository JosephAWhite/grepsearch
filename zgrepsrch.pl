#!/usr/bin/perl
#
#	zgrepsrch.pl	zgrep search a list of patterns against a fastq.gz file
#
#	J.White, J.Comander	2015-06-03	v.5
#
use strict 'vars';
use Getopt::Std;
use IO::CaptureOutput qw/capture qxx qxy/;
use File::Basename;

my @args = @ARGV;
my $usage = "perl $0 -i input -o output -p patterns_file -n(no rev_comp) -D(debug)";
die "$usage\n" if(@ARGV < 1);

my %opts;
getopts("Dni:o:p:w:",\%opts);
my $infile = $opts{'i'};
my $output = $opts{'o'};
my $patterns = $opts{'p'};
my $debug = $opts{'D'};
my $nocomp = $opts{'n'};
my $workdir = $opts{'w'};

die "No search patterns supplied" if ! $patterns; 
my $probedir = dirname($patterns);
chomp($probedir);

if($debug) {
	print "infile: $infile\noutput file: $output\nprobes: $patterns\n";
	print "nocomp: $nocomp\nworkdir: $workdir\nprobe dir: $probedir\n";
}

if($output && $workdir) {
	open(OUT,">>$workdir/$output") || die "Could not open output file, $output; $!\n";
	print OUT "perl $0 @args\n";
} elsif($output) {
	open(OUT,">>$output") || die "Could not open output file, $output; $!\n";
	print OUT "perl $0 @args\n";
}

my $ctr;
open(REGEX, $patterns) || die "FILE $patterns NOT FOUND - $!\n";
while(<REGEX>) {
	chomp;
	$ctr++;
	my ($label,$regex_mut,$regex_wt,$ref_mut,$ref_wt) = split /\t/, $_;
	my $regex_mut_rev = '';
	my $regex_wt_rev = '';
	my $refsrch;
	my $wtsrch;
	my $mutseq;
	my $wtseq;
	# check for inserted mutant sequence file
	if($ref_mut) {
		$refsrch = 1;
		$ref_mut = "$probedir/$ref_mut";
		print "$ref_mut\n" if $debug;
		open(MUT,$ref_mut) || die "Could not open mutant reference file.\n";
		# if this is a fasta file, skip the first line
		if(index($ref_mut,".fasta") || index($ref_mut,".fa")) {
			<MUT>;
		}
		while(<MUT>) {
			chomp;
			$mutseq .= $_;
		}
		close(MUT);
	} else {
		$refsrch = 0;
	}
	# check for reference sequence file
	if($ref_wt) {
		$wtsrch = 1;
		$ref_wt = "$probedir/$ref_wt";
		print "$ref_wt\n" if $debug;
		open(WT,$ref_wt) || die "Could not open wildtype reference file.\n";
		# if this is a fasta file, skip the first line
		if(index($ref_wt,".fasta") || index($ref_wt,".fa")) {
			<WT>;
		}
		while(<WT>) {
			chomp;
			$wtseq .= $_;
		}
		close(WT);
	} else {
		$wtsrch = 0;
	}
	# handle 'no complementation' 
	unless($nocomp) {
		$regex_mut_rev = &revcomp($regex_mut);
		$regex_mut = ($regex_mut . "\\\|$regex_mut_rev");
		$regex_wt_rev = &revcomp($regex_wt);
		$regex_wt = ($regex_wt . "\\\|$regex_wt_rev");
	}
	# results array
	my @results;
	# search string hash
	my %regexp = (mut => $regex_mut, wt => $regex_wt, label => $label );
	foreach my $reg (sort keys %regexp) {
		# main loop
		next if $reg eq 'label';
		my $mutctr = 0; my $wtctr = 0;
		my $regexp = $regexp{$reg};
		my $label = $regexp{'label'} . "_$reg";
		next if $reg eq '';
		my $cmd = "zgrep '$regexp' $infile";
		print "processing zgrep $label $regexp $infile \n";
		# capture stdout
		my $stdout = qxx( $cmd );
		chomp($stdout);
		my @zhits = split /\W+/, $stdout;
		if($debug) {
			$" = "\n";
			print "@zhits\n";
		}
		# mutant hits
		my $hitctr = scalar @zhits;
		print "total hits hitctr $hitctr\n";
		push @results, $hitctr;

		if($refsrch) {
		# secondary search against mutant reference
			foreach my $hit (@zhits) {
				my $rev_hit = &revcomp($hit);
				my $pattern = ($hit . "\\\|$rev_hit");
				my $cmd = "grep -c \"$pattern\" $ref_mut";
				print OUT "mut ref hits: $cmd\n" if $debug;
				my $stdout = qxx( $cmd );
				chomp($stdout);
				print "$stdout\n" if $debug;
				$mutctr++ if $stdout > 0;
			}
			print "$mutctr\n" if $debug;
			print "matching mutant reference $mutctr\n";
		}
		push @results, $mutctr;
		if($wtsrch) {
		# secondary search against wt reference
                        foreach my $hit (@zhits) {
                                my $rev_hit = &revcomp($hit);
                                my $pattern = ($hit . "\\\|$rev_hit");
                                my $cmd = "grep -c \"$pattern\" $ref_wt";
				print OUT "wt ref hits: $cmd\n" if $debug;
                                my $stdout = qxx( $cmd );
                                chomp($stdout);
                                $wtctr++ if $stdout > 0;
                        }
			print "$wtctr\n" if $debug;
			print "matching wt reference $wtctr\n";
		}
		push @results, $wtctr;
	}
	$" = "\t";
	# determine heterozygous/homozygous status at mutant site
	my $hetratio;
	my $call;
	if($results[1] > 0) {
		$hetratio = $results[1] / ($results[1] + $results[5]);
		if($hetratio == 1) {
			$call = "mak_alu_homozygous_mutant";
		} elsif($hetratio >= 0.8) {
			$call = "mak_alu_probable_homozygous_mutant_error";
		} elsif($hetratio >= 0.2) {
			$call = "mak_alu_heterozygous_mutant";
		} else {
			$call = "mak_alu_probable_heterozygous_mutant_error";
		}
	} else {
		if($results[0] > 0) {
			$call = "probable_wildtype";
		} else {
			$call = "wildtype or no coverage";
		}
	}
	print OUT "@results\t$label\t$call\t$infile\n";
	@results = ();
}

close(OUT);
close(REGEX);

# reverse complement sequence
sub revcomp {
	my $seq = shift();
	$seq = uc($seq);
	my @comp = qw(T G C A A);
	my $rc = '';
	#split into array of bytes
	my @bases = split //, $seq;
	foreach my $byte (@bases) {
		my $index = index("ACGTU",$byte);
		$rc .= $comp[$index];
	}
	$rc = reverse($rc);
	if(length($seq) != length($rc)) { $rc = -1; }
	return $rc;
}
