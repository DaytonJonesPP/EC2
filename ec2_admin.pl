#! /usr/bin/env perl
#===============================================================================
#
#         FILE: ec2_admin.pl
#
#        USAGE: ec2_admin.pl
#
#  DESCRIPTION:
#
#      OPTIONS: ---
# REQUIREMENTS: ---
#        NOTES: ---
#       AUTHOR: Dayton Jones (dj), djones@proofpoint.com
#      COMPANY: Proofpoint
# ORGANIZATION: Social Media Products
#      VERSION: 0.1.0
#      CREATED: 05/06/2017 02:18:53 PM
#     REVISION: ---
#===============================================================================
use Getopt::Long;
use Term::ANSIColor;
eval {
	require VM::EC2;
    VM::EC2->import() ;
};
if ($@) {
	die "\n\t!!! Error: VM::EC2 module not found\n\tPlease install the VM::EC2 perl module\n\n";
}

## Variable Declaration
chop($PROGNAME=`basename $0`);
chop($PROGNAME_SHORT=`basename -s .pl $0`);
$version="0.1.0";
$USER=$ENV{USER};
chop($RUNID=`/bin/date +%Y%m%d%H%M%S`);
$OFILE="$PROGNAME_SHORT" . "-$USER" . "_$RUNID";
$sw=`tput cols`;

if ($ENV{'EC2_REGION'}) {$ec2_region =  $ENV{'EC2_REGION'}};
if ($ENV{'EC2_ACCESS_KEY'}) {$ec2_access_id =  $ENV{'EC2_ACCESS_KEY'}};
if ($ENV{'EC2_SECRET_KEY'}) {$ec2_secret_key =  $ENV{'EC2_SECRET_KEY'}};
if ($ENV{'EC2_URL'}) {$ec2_url =  $ENV{'EC2_URL'}};

## Subroutines
sub _version {
    print colored ['green'],"$PROGNAME v$version\n";
}

sub _help {
    _version;
    print qq|

    Use:
       $PROGNAME --instances\|--regions {--help\|--version\|--search <type=item>\|--config <opt=val>}

        --instances                 display instance info
        --regions                   displays region/zone/vpc info
        --output <format>           print to file as well as screen
            valid formats:
                text                output to text file
                json                output to json formatted file
        --help                      displays this help screen
        --version                   displays script version
        --search <type=item>        search for specific items
            valid searches:
                instance=<instance id>
                name=<hostname>
        --conf <opt=val>            set EC2 config options
            valid options:
                region=<region>
                id=<id>
                url=<endpoint>
                key=<secret key>

    * Short options can be given as well: "-i" instead of --instances, etc

    * Users can set environment variables or use "--conf <opt=val>" to specify EC2 options
        export EC2_SECRET_KEY=<aws secret key id>
        export EC2_ACCESS_KEY=<aws access id>
        export EC2_REGION=<aws region to query>
        export EC2_URL=<API endpoint to use>

    "--config <opt=val>" will override environment variables

    * At least one of "--instances" or "--regions" needs to be given, both can be given.

    * Multiple "--search" options can be specified, user can mix types:
        "$PROGNAME -s name=host1.mydomain.com -s inst=i-237f8d --search name=test1"

    * Searches will take place in all regions, for both names and instances.  Results will
        be shown and then the next search request will be processed.

    * Hostname searches automatically will be wildcard searches (*<name>*) so the more
        exact the name entered, the more precise the results.

    * Multiple "--output" formats can be selected

    To do:
        * Ability to create {instances,vpcs,?}
        * Fix (implement) JSON output
        * ?


|;
}

sub _term_exit {
    print colored ['red'],"\n$PROGNAME: Terminated\n";
	$EC="1";
	if ($output){
		&_print_output ("$PROGNAME: Terminated\n");
	}
    _myexit ($EC);
}

sub _int_exit {
    print colored ['yellow'],"\n$PROGNAME: " . colored ['red'], "Aborted by user\n";
	$EC="1";
	if ($output) {
		&_print_output ("Aborted by user\n");
	}
    _myexit ($EC);
}

sub _print_output{
	$out_info=shift;
    foreach $t (@OUTPUT){
        if (($t eq "") || ($t eq "text") || ($t eq "t")){
			print TXT ($out_info);
        } elsif (($t eq "json") || ($t eq "j")) {
			print JSON ($out_info);
		}
    }
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
    if (! $ec2_region) {
        $missing="true";
        $var=$var . " \"ec2_region\"";
    }
    if (! $ec2_url) {
        $missing="true";
        $var=$var . " \"ec2_url\"";
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
    	'version'       	=>\$VERSION,
    	'config=s'          =>\@CONFIG_OPTIONS,
	 	'regions'	  		=>\$SHOW_REGIONS,
	 	'instances'			=>\$SHOW_INSTANCES,
        'search=s'          =>\@SEARCHES,
        'output:s'          =>\@OUTPUT,
        'help|?'        	=>\$HELP);

    &_check_vars;

	if ($HELP) {
    	_help;
        &_myexit;
    }

    if (@OUTPUT){
        $output="true";
        foreach (@OUTPUT){
			if (($_ eq "text") || ($_ eq "") || ($_ eq "t")) {
				$my_OFILE = $OFILE . ".txt";
				open(TXT,">>/tmp/$my_OFILE");
			} elsif (($_ eq "json") || ($_ eq "j")) {
				$my_OFILE = $OFILE . ".json";
				open(JSON,">>/tmp/$my_OFILE");
			} else {
				$EC="2";
				print "Invalid output method selected: only text or json supported\n";
				_myexit ($EC);
			}
        }
    }
    if (@CONFIG_OPTIONS) {
        foreach $c (@CONFIG_OPTIONS) {
            ($c_def,$c_val)=split(/=/,$c);
            if ($c_def eq "region"){
                $ec2_region=$c_val;
            } elsif ($c_def eq "id"){
                $ec2_access_id=$c_val;
            } elsif ($c_def eq "key"){
                $ec2_secret_key=$c_val;
            } elsif ($c_def eq "url"){
                $ec2_url=$c_val;
            } else {
                $bad_opt= $bad_opt . $c_def . ":" . $c_val . " ";
            }
        }
        if ($bad_opt) {
			$EC="1";
            printf ("%s %s\n\n", colored("Unknown option specfied:",'red'),colored($bad_opt,'yellow'));
            _help;
            _myexit ($EC);
        }
    }

    if (@SEARCHES) {
        print colored ['green'],"Gathering region info...\n\n";
		&_print_output ("Gathering region info...\n\n");
        &_get_region_info;
        foreach $search (sort @SEARCHES) {
            ($type,$what)=split(/=/,$search);
            if ($type eq "instance"){
                $s_inst=$s_inst . ":" . $what;
                $si="true";
            } elsif ($type eq "name") {
                $s_name=$s_name . ":" . $what;
                $sn="true";
            }
        }
        if ($si){
            foreach ($s_inst){
                my @values = split(/:/, $s_inst);
                foreach my $s (@values){
                    next if ($s eq "");
                    print "Searching for instance \"$s\" in all regions...\n";
					&_print_output ("Searching for instance \"$s\" in all regions...\n");
                    foreach my $r (@r_name){
                        &_search_instances($r,$s);
                        $count=scalar(@i);
                        if ($count lt "1"){
                            #print "\t$s not found in $r\n";
                        } else {
		                    foreach (@i) {
                                printf("%s%s%s\n", "[", colored($_,'yellow'), "]");
								&_print_output ("[$_]\n");
        	                    _show_instances($_);
    	                    }
                        }
                    }
                }
            }
        }
        if ($sn){
            foreach ($s_name){
                my @values = split(/:/, $s_name);
                foreach my $s (@values){
                    next if ($s eq "");
                    $s="*" . $s . "*";
                    print "Searching for \"$s\" in all regions...\n";
					&_print_output ("Searching for \"$s\" in all regions...\n");
                    foreach my $r (@r_name){
                        &_search_hosts($r,$s);
                        $count=scalar(@i);
                        if ($count lt "1"){
                            #print "host not found\n";
                        } else {
                            _show_hosts(@i);
                        }
                    }
                }
            }
        }
    }

    if ($SHOW_REGIONS) {
    	&_show_regions;
    }

    if ($SHOW_INSTANCES) {
		&_get_instances;
		foreach (@i) {
        	printf("%s%s%s\n", "[", colored($_,'yellow'), "]");
			&_print_output ("[$_]\n");
        	_show_instances($_);
    	}
    }

    if ($VERSION) {
        _version;
       _myexit;
    }

}

sub _get_region_info {
    $ec2       = VM::EC2->new(-access_key => $ec2_access_id,-secret_key => $ec2_secret_key,-endpoint => $ec2_url) or die "Error: $!\n";
    @regions   = $ec2->describe_regions();
    foreach (sort @regions) {
        $name    = $_->regionName;
        push @r_name,$name;
    }
        return (@r_name,@regions);
}

sub _show_regions {
    &_get_region_info;
    print colored ['green'],"Gathering region info...\n\n";
	&_print_output ("Gathering region info...\n\n");
    foreach (sort @regions) {
        $name    = $_->regionName;
        $url     = $_->regionEndpoint;
        @zones   = $_->zones;
        printf("%s%s%s\n", "[", colored("$name",'yellow'),"]");
        printf("%-30s %-20s\n", colored("    Endpoint:",'blue'),$url);
        printf("%-30s\n", colored("    Zones:",'blue'));
		&_print_output ("[$name]\n");
		&_print_output ("\tEndpoint: $url\n");
		&_print_output ("\tZones:\n");
        foreach (sort @zones) {
            printf("%-21s %-50s\n","    ",$_);
			&_print_output ("\t\t$_\n");
        }
        $ec2 = VM::EC2->new(-access_key => $ec2_access_id,-secret_key => $ec2_secret_key,-region=>$name) or die "Error: $!\n";
        @vpc = $ec2->describe_vpcs();
		if (@vpc) {
			printf("%-30s\n", colored("    VPCs:",'blue'));
			&_print_output ("\tVPCs:\n");
        	foreach $v (sort @vpc){
				printf("%-21s %-50s\n","    ",$v);
				&_print_output ("\t\t$v\n");
			}
		}
        print "\n";
		&_print_output ("\n");
    }
    print "\n";
	&_print_output ("\n");
}

sub _search_hosts () {
    $s_region=shift;
    $s_name=shift;
    if ($s_region) {$ec2_region = $s_region;}
    $ec2 = VM::EC2->new(-access_key => $ec2_access_id,-secret_key => $ec2_secret_key,-region=>$ec2_region,-endpoint => $ec2_url) or die "Error: $!\n";
    if ($s_name){
        #print "Searching for $s_name in $s_region...\n";
        @i = $ec2->describe_instances(-filter=>{'tag:Name'=> $s_name});
    } else {
		$EC="1";
        print "\t!!! Error: No name was specified\n";
        _myexit ($EC);
    }
    return @i;
}

sub _show_hosts {
    foreach $id (@i) {
        next if ($id eq "");
        printf("%s%s%s\n", "[", colored($id,'yellow'), "]");
		&_print_output ("[$id]\n");
        _show_instances($id);
    }
}

sub _search_instances () {
    $s_region=shift;
    $s_id=shift;
    if ($s_region) {$ec2_region = $s_region;}
    $ec2 = VM::EC2->new(-access_key => $ec2_access_id,-secret_key => $ec2_secret_key,-region=>$ec2_region,-endpoint => $ec2_url) or die "Error: $!\n";
    if ($s_id){
        @i = $ec2->describe_instances(-instance_id=>$s_id);
        @i = sort @i;
    } else {
        @i = $ec2->describe_instances();
        @i = sort @i;
    }
    return @i;
}
sub _get_instances {
    &_search_instances;
    printf("%s %s...\n", colored("Getting list of instances in",'green'), colored($ec2_region,'cyan'));
	&_print_output ("Getting list of instances in $ec2_region\n");
    $count=scalar(@i);
    if ($count lt "1"){
		$EC="1";
        print colored ['red'],"0 instances found, please verify your ID and Secret key if this is incorrect\n";
		&_print_output ("0 instances found, please verify your ID and Secret key if this is incorrect\n");
        _myexit ($EC);
    }
    printf("%s %s %s %s\n\n",colored("Found",'green'),colored($count,'magenta'),colored("instances in",'green'),colored($ec2_region,'cyan'));
	&_print_output ("Found $count instances in $ec2_region\n\n");
}

sub _show_instances {
    $id=shift;
    $instance = $ec2->describe_instances(-instance_id=>$id);
    $placement     = $instance->placement;
    $reservationId = $instance->reservationId;
    $imageId       = $instance->imageId;
    $private_ip    = $instance->privateIpAddress;
    $public_ip     = $instance->ipAddress;
    $private_dns   = $instance->privateDnsName;
    $public_dns    = $instance->dnsName;
    $time          = $instance->launchTime;
    $status        = $instance->current_status;
    $vpc           = $instance->vpcId;
    $subnet        = $instance->subnetId;
    $type          = $instance->instanceType;
    $data          = $instance->userData;
    @groups        = $instance->groupSet;
    $tags          = $instance->tags;

    if ($tags){
		if ($tags->{Name}) {
    		printf("%-30s %-50s\n", colored("    Hostname",'blue'),$tags->{Name});
			&_print_output ("\tHostname:\t$tags->{Name}\n");
		}
    }

    printf("%-30s %-50s\n", colored("    Instance Type:",'blue'),$type);
    printf("%-30s %-50s\n", colored("    Zone:",'blue'),$placement);
    printf("%-30s %-50s\n", colored("    VPC:",'blue'),$vpc);
    printf("%-30s %-50s\n", colored("    Subnet:",'blue'),$subnet);
    printf("%-30s %-50s\n", colored("    Reservation:",'blue'),$reservationId);
    printf("%-30s %-50s\n", colored("    Image ID:",'blue'),$imageId);
    printf("%-30s %-50s\n", colored("    Private IP:",'blue'),$private_ip);
    printf("%-30s %-50s\n", colored("    Public IP:",'blue'),$public_ip);
    printf("%-30s %-50s\n", colored("    Private Name:",'blue'),$private_dns);
    printf("%-30s %-50s\n", colored("    Public Name:",'blue'),$public_dns);
    printf("%-30s %-50s\n", colored("    Launch Time:",'blue'),$time);
    printf("%-30s %-50s\n", colored("    State:",'blue'),$status);
	&_print_output ("\tInstance Type:\t$type\n");
	&_print_output ("\tZone:\t\t$placement\n");
	&_print_output ("\tVPC:\t\t$vpc\n");
	&_print_output ("\tSubnet:\t\t$subnet\n");
	&_print_output ("\tReservation:\t$reservationId\n");
	&_print_output ("\tImage ID:\t$imageId\n");
	&_print_output ("\tPrivate IP:\t$private_ip\n");
	&_print_output ("\tPublic IP:\t$public_ip\n");
	&_print_output ("\tPrivate Name:\t$private_dns\n");
	&_print_output ("\tPublic Name:\t$public_dns\n");
	&_print_output ("\tLaunch Time:\t$time\n");
	&_print_output ("\tState:\t\t$status\n");

    if ($data){
        print colored ['blue'],"    User Data:\n";
		&_print_output ("\tUser Data:\n");
        @lines = split /\n/, $data;
        foreach $line (@lines) {
            printf("%-21s %-50s\n","    ",$line);
			&_print_output ("\t\t\t$line\n");
        }
        print "\n";
		&_print_output ("\n");
    }
    if ($tags){
        print colored ['blue'],"    Tags:\n";
		&_print_output ("\tTags:\n");
		foreach my $key (sort keys %$tags) {
    		$value = $tags->{$key};
    		printf("%-21s %-50s\n","    ","$key: $value");
			&_print_output ("\t\t\t$key: $value\n");
		}
        print "\n";
		&_print_output ("\n");

    }
    if (@groups){
        print colored ['blue'],"    Security Groups:\n";
		&_print_output ("\tSecurity Groups:\n");
	    for $g (sort @groups){
		    $gid		= $g->groupId;
		    $gname		= $g->groupName;
		    $sg 		= $ec2->describe_security_groups($g);
		    @gperms_i		= $sg->ipPermissions;
		    @gperms_e		= $sg->ipPermissionsEgress;
			printf("%-21s %-50s\n","    ","ID: $gid");
			printf("%-26s %-50s\n","    ","Name: $gname");
			&_print_output ("\t\t\tID: $gid\n");
			&_print_output ("\t\t\t\tName: $gname\n");
			if (@gperms_i) {
				printf("%-26s %-50s\n","    ","Ingress Rules:");
				&_print_output ("\t\t\t\tIngress Rules:\n");
				for $i (@gperms_i) {
         			$protocol = $i->ipProtocol;
         			$fromPort = $i->fromPort;
         			$toPort   = $i->toPort;
         			@ranges   = $i->ipRanges;
					next if ($protocol eq "-1");
					printf("%-30s %-50s\n","    ","$protocol from:$fromPort to: $toPort");
					&_print_output ("\t\t\t\t\t$protocol from:$fromPort to: $toPort\n");
					for $r (sort @ranges) {
						printf("%-35s %-50s\n","    ","Source IP: $r");
						&_print_output ("\t\t\t\t\t\tSource IP: $r\n");
					}
      			}
			}
			if (@gperms_e){
				printf("%-26s %-50s\n\n","    ","Egress Rules:");
				&_print_output ("\t\t\t\tEgress Rules:\n\n");
				for $j (@gperms_e) {
         			$protocol = $j->ipProtocol;
         			$fromPort = $j->fromPort;
         			$toPort   = $j->toPort;
         			@ranges   = $j->ipRanges;
					next if ($protocol eq "-1");
					printf("%-30s %-50s\n","    ","$protocol from:$fromPort to: $toPort");
					&_print_output ("\t\t\t\t\t$protocol from:$fromPort to: $toPort\n");
					for $r (sort @ranges) {
						printf("%-35s %-50s\n","    ","Destination IP: $r");
						&_print_output ("\t\t\t\t\t\tDestination IP: $r\n");
					}
      			}
			}
	    }
    }
    print "\n";
	&_print_output ("\n");
}

sub _myexit{
	$EC=shift;
	if ($EC eq "2") {
		system("rm -f /tmp/$OFILE.*");
	}
	if ((@OUTPUT) && (! $EC eq "2")) {
		foreach (@OUTPUT) {
			if (($_ eq "text") || ($_ eq "") || ($_ eq "t")) {
				$myOFILE=$OFILE . ".txt";
				close($myOFILE);
				push @files,"/tmp/$myOFILE";
			} elsif (($_ eq "json") || ($_ eq "j")) {
				$myOFILE=$OFILE . ".json";
                close($myOFILE);
				push @files,"/tmp/$myOFILE";
			}
		}
		print ( "=" x $sw);
		print "\nOutput written to:\n";
		foreach (@files){
			print "\t$_\n";
		}
		print "\n";
	}
	exit $EC;
}

## Main
$SIG {"TERM"} = \&_term_exit;
$SIG {"HUP"} = \&_term_exit;
$SIG {"INT"} = \&_int_exit;

system("clear");

if (! $ARGV[0]) {
	$EC="1";
    _help;
    _myexit ($EC);
}

# process options and gather/display results in _get_opts
_get_opts;

# cleanup and exit
_myexit;
