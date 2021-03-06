#! /usr/bin/env perl
#===============================================================================
#
#         FILE: s3_admin.pl
#
#        USAGE: s3_admin.pl
#
#  DESCRIPTION: A useful script to poll AWS::S3 and display infomation about your
#               S3 buckets
#
#      OPTIONS: ---
# REQUIREMENTS: AWS id/secret credentials
#        NOTES: ---
#       AUTHOR: Dayton Jones (dj), djones@proofpoint.com
#      COMPANY: Proofpoint
# ORGANIZATION: Social Media Products
#      VERSION: 0.1.0
#      CREATED: 05/06/2017 02:18:53 PM
#     REVISION: ---
#===============================================================================
## delete files from bucket
##  $bucket->delete_key('reminder.txt') or die $s3->err . ": " . $s3->errstr;
##  $bucket->delete_key('1.JPG')        or die $s3->err . ": " . $s3->errstr;


# Test for required modules
BEGIN {
    @MODULES=("Getopt::Long","JSON","List::MoreUtils","Term::ANSIColor","Amazon::S3");
    foreach $m (@MODULES) {eval("use $m");if ($@) {warn "\n\t!!! Error: $m module not found!!!\n\n\tPlease install the $m perl module:\n\t\'perl -MCPAN -e 'install $m\' or \'cpan $m\'\n\n";$missing="yes";}}
    if ($missing) {
        exit 1;
    }
}

## Variable Declaration
chop($PROGNAME=`basename $0`);
chop($PROGNAME_SHORT=`basename -s .pl $0`);
$version="0.1.0";
#$USER=$ENV{USER};
#chop($RUNID=`/bin/date +%Y%m%d%H%M%S`);
#$OFILE="$PROGNAME_SHORT" . "-$USER" . "_$RUNID";
$sw=`tput cols`;

if ($ENV{'EC2_ACCESS_KEY'}) {$ec2_access_id =  $ENV{'EC2_ACCESS_KEY'}};
if ($ENV{'EC2_SECRET_KEY'}) {$ec2_secret_key =  $ENV{'EC2_SECRET_KEY'}};

$s3 = Amazon::S3->new({aws_access_key_id=> $ec2_access_id,aws_secret_access_key => $ec2_secret_key,retry=> 1});

sub _version {
    print colored ['green'],"$PROGNAME v$version\n";
}

sub _term_exit {
    print colored ['red'],"\n$PROGNAME: Terminated\n";
    $EC="1";
    if ($output){
        &_print_txt ("$PROGNAME: Terminated\n");
    }
    _myexit ($EC);
}

sub _int_exit {
    print colored ['yellow'],"\n$PROGNAME: " . colored ['red'], "Aborted by user\n";
    $EC="1";
    if ($output) {
        &_print_txt ("Aborted by user\n");
    }
    _myexit ($EC);
}

sub _myexit{
    $EC=shift;
    exit $EC;
}

sub _help {
    _version;
    print qq|

    Use:
       $PROGNAME [ --bucket <bucket name> \| --help \| --version ]

	When run, $PROGNAME_SHORT will list all current buckets.  If <bucket name> is specified
	then after all buckets are listed, the contents of the specified bucket will be
	enumerated and info given on each "key"

|;
}

sub _get_s3_buckets {
	$response = $s3->buckets;

	$owner_id		=	$response->{owner_id};
	$owner_name		=	$response->{owner_displayname};
	$bucket_list	=	$response->{buckets};

	return($owner_id,$owner_name,$bucket_list);
}

sub _list_s3_buckets {
	$b_count="0";
	&_get_s3_buckets;

    printf("%s %-50s\n", colored("Owner ID:  ",'blue'),$owner_id);
    printf("%s %-50s\n", colored("Owner Name:",'blue'),$owner_name);
    print colored ['blue'],"Buckets:\n";
	foreach my $bucket (@{$bucket_list}){
		$b_count++;
        printf("%-30s %-50s\n", colored("    Name:",'cyan'),$bucket->bucket);
        printf("%-30s %-50s\n\n", colored("    Creation Date:",'cyan'),$bucket->creation_date);
	}
	print "\nFound $b_count buckets\n\n";
}

sub _list_s3_bucket_contents {
	my $b=shift;
	my $f_count="0";
	my $tot_bytes="0";
#    $lc="0";
	$bucket = $s3->bucket($b) or die $s3->err . ": " . $s3->errstr;
	print "\nGetting contents of S3 bucket: [$b] \n\tThis might take a while...\n\n";
    $time_s=time();
	$response = $bucket->list_all or die $s3->err . ": " . $s3->errstr;
	if (@{ $response->{keys} }) {
        $time_e=time();
        $l_seconds= $time_e - $time_s;
        &_sec_convert($l_seconds);
        printf("\b%s%s%s\n", "[", colored($b,'yellow'), "]");
  		foreach my $key ( @{ $response->{keys} } ) {
			$f_count++;
     		my $key_name = $key->{key};
      		my $key_size = $key->{size};
			$tot_bytes = $tot_bytes + $key_size;
			&_prettyBytes($key_size);
			my $key_lm = $key->{last_modified};
			my $key_etag = $key->{etag};
			my $key_class = $key->{storage_class};
			my $key_ownerID = $key->{owner_id};
			my $key_OwnerName = $key->{owner_displayname};

            printf("%-30s %-50s\n", colored("    Item:",'blue'),$key_name);
            printf("%-40s %-50s\n", colored("       Owner:",'blue'),$key_OwnerName);
            printf("%-40s %-50s\n", colored("       Last Modified:",'blue'),$key_lm);
            printf("%-40s %-50s\n", colored("       MD5 sum:",'blue'),$key_etag);
            printf("%-40s %-50s\n", colored("       Type:",'blue'),$key_class);
            printf("%-40s %-50s\n\n", colored("       Size:",'blue'),$b_size);
  		}
		$f_count =~ s/(\d{1,3}?)(?=(\d{3})+$)/$1,/g; # add thousands seperator
		&_prettyBytes($tot_bytes);
		print "Found $f_count items in [$b], search took $run_time\nTotal size: $b_size\n\n";
#		print "See https://aws.amazon.com/s3/storage-classes/ for Type definitions\n\n";
	}else{
		print colored ['red'],("\t\tNo contents found in [$b]\n\n");
	}
}

sub _prettyBytes {
	@sizes=qw( B KB MB GB TB PB);
	$b_size = shift;
    $i = 0;
    while ($b_size > 1024) {
        $b_size = $b_size / 1024;
        $i++;
    }
    if ($sizes[$i] eq B){
        $b_size = "$b_size Bytes";
    }else{
        $b_size=sprintf ("%.2f $sizes[$i]", $b_size);
    }
    return($b_size);
}

sub _sec_convert {
    $total_sec=shift;
	if ($total_sec lt "1"){$run_time=$total_sec ." seconds"}
	else {
    	$secs=$total_sec%60;
    	$mins=($total_sec/60)%60;
    	$hours=($total_sec/(60*60))%24;
    	$days=int($total_sec/(24*60*60));
    	if ($days){$run_time= "$days day ";}
    	if ($hours){$run_time="$run_time" . "$hours hours ";}
    	if ($mins){$run_time="$run_time" . "$mins minutes ";}
    	if ($secs){$run_time="$run_time" . "$secs seconds";}
	}
    return($run_time);
}

sub _check_vars {
    if (! $ec2_access_id) {
        $missing="true";
        $var=$var . " \"ec2_access_id\"";
    }
    if (! $ec2_secret_key) {
        $missing="true";
        $var=$var . " \"ec2_secret_key\"";
    }
    if ($missing){
        $EC="1";
        print colored ['red'],("!" x $sw);
        printf("\n\n\t\t%s\n\t\t%s\n\n", colored("Please specify the following options:",'red'),colored("$var",'yellow'));
        print colored ['red'],("!" x $sw);
        print "\n\n";
        _help;
        _myexit ($EC);
    }
}

sub _get_opts {
    GetOptions(
        'version'           =>\$VERSION,
        'bucket:s'         	=>\$BUCKET,
#        'output:s'          =>\@OUTPUT,
        'help|?'            =>\$HELP);

    if ($HELP) {
        _help;
        &_myexit;
    }

    if ($VERSION) {
        _version;
       _myexit;
    }

	&_check_vars;
}

## Main
$SIG {"TERM"} = \&_term_exit;
$SIG {"HUP"} = \&_term_exit;
$SIG {"INT"} = \&_int_exit;

print "\033[2J";    #clear the screen

# process options and gather/display results in _get_opts
#$commandline = join " ", $0, @ARGV;
_get_opts;

# list all buckets
_list_s3_buckets;

# enumerate contents of $BUCKET
if ($BUCKET){
	_list_s3_bucket_contents($BUCKET);
}

#if ($ARGV[0]){
#    $lb = $ARGV[0];
#} else {
#    ### get random bucket
#    $hash = { mykey => \@{$bucket_list} };
#    $b = $hash->{mykey}[ rand(@{ $hash->{mykey} }) ];
#    $lb = $b->{bucket};
#    ###
#}
#_list_s3_bucket_contents($lb);
