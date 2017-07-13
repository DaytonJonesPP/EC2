#! /usr/bin/env perl
#===============================================================================
#
#         FILE: ec2_admin.pl
#
#        USAGE: ec2_admin.pl
#
#  DESCRIPTION: A useful script to poll AWS and display infomation about your
#               EC2 environment
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
# Test for required modules
BEGIN {
    @MODULES=("Switch","Getopt::Long","JSON","List::MoreUtils","Term::ANSIColor","VM::EC2");
    foreach $m (@MODULES) {eval("use $m");if ($@) {warn "\n\t!!! Error: $m module not found!!!\n\n\tPlease install the $m perl module:\n\t\'perl -MCPAN -e 'install $m\' or \'cpan $m\'\n\n";$missing="yes";}}
    if ($missing) {
        exit 1;
    }
}

## Variable Declaration
chop($PROGNAME=`basename $0`);
chop($PROGNAME_SHORT=`basename -s .pl $0`);
$version="0.1.0";
$USER=$ENV{USER};
chop($RUNID=`/bin/date +%Y%m%d%H%M%S`);
$OFILE="$PROGNAME_SHORT" . "-$USER" . "_$RUNID";
$sw=`tput cols`;
undef $cruft;

if ($ENV{'EC2_REGION'}) {$ec2_region =  $ENV{'EC2_REGION'}};
if ($ENV{'EC2_ACCESS_KEY'}) {$ec2_access_id =  $ENV{'EC2_ACCESS_KEY'}};
if ($ENV{'EC2_SECRET_KEY'}) {$ec2_secret_key =  $ENV{'EC2_SECRET_KEY'}};
if ($ENV{'EC2_URL'}) {$ec2_url =  $ENV{'EC2_URL'}};

## Subroutines
sub _version {
    print colored ['green'],"$PROGNAME v$version\n";
}

sub _more_info {
    _version;
    print qq|
    * Short options can be given as well: "-i" instead of --instances, etc

    * Users can set environment variables or use "--conf <opt=val>" to specify EC2 options
        export EC2_SECRET_KEY=<aws secret key id>
        export EC2_ACCESS_KEY=<aws access id>
        export EC2_REGION=<aws region to query>
        export EC2_URL=<API endpoint to use>

      if no URL is given, $PROGNAME_SHORT will pick the default for the given region

    "--config <opt=val>" will override environment variables

    * When using --instances or --ami, only results for the current ec2_region will be shown.
        If you want to see all AMIs, use "--region" which will show AMI, VPC, and Zones for all.
        If you want to see all instances, in all regions, you'll have to search instances using
          a wildcard (ie: "--search name=*")

    * Multiple "--search" options can be specified, user can mix types:
        "$PROGNAME -s name=host1.mydomain.com -s inst=i-237f8d --search name=test1"

    * Searches will take place in all regions, for both names and instances.  Results will
        be shown and then the next search request will be processed.  Only non-terminated
        instances will be searched for and shown.

    * Tag searches are case sensitive, occur in all regions, and multiple tags can be given
        (with seperate "-s tag=" directivies)
        Proper use: -s tag=<item:value>
            Ex:
                "$PROGNAME --search tag=Version:2.0.1"
                "$PROGNAME -s tag=component:web -s tag=owner:Fred"

    *  Only hostname and role searches are wildcard searches (*<name>*) so the more
        exact the name entered, the more precise the results.  Searches are case
        sensitive though.

    * Multiple "--output" formats can be selected

    To do:
        * Ability to create {instances,vpcs,?}
        * Control instances (stop, start, terminate)
        * Search by:
            State (running, terminated, etc)
            Compound search - "type=m4.large AND region=us-west-2"
        * Optimize and remove duplication
            * do region lookup once and store instead of calling for every command
            * breakout any duplicated routines (search, etc)
        * Typo checks, general cleanup (remove extra comments, etc)
        * ?


|;
    exit 0;
}

sub _help {
    _version;
    print qq|

    Use:
       $PROGNAME --instances\|--regions\|--ami {--help\|--version\|--search <type=item>\|--config <opt=val>}

        --instances                 display non-terminated instances in current region
        --regions                   displays info on all regions
                                        zones vpcs AMIs
        --ami                       displays AMI info for current region
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
                type=<instance type>
                tag=<item:value>
                role=<IAM Role>
        --conf <opt=val>            set EC2 config options
            valid options:
                region=<region>
                id=<id>
                url=<endpoint>
                key=<secret key>

	See "$PROGNAME --more" for more information and usage

|;
}

sub _term_exit {
    print colored ['red'],"\n$PROGNAME: Terminated\n";
	$EC="1";
        if ($print_txt){printf TXT ("\n\t%s\n","!!! $PROGNAME: Terminated !!!");}
    _myexit ($EC);
}

sub _int_exit {
    print colored ['yellow'],"\n$PROGNAME: " . colored ['red'], "Aborted by user\n";
	$EC="1";
        if ($print_txt){printf TXT ("\n\t%s\n", "!!! Aborted by user !!!");}
    _myexit ($EC);
}

sub _mask_it {
    use List::MoreUtils qw(pairwise);
    $u_type=shift;
	if ($u_type eq "secret"){
		my $mask='XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX';
		my @mask=split( '', $mask );
		my @secret=split( '', $ec2_secret_key );
		$masked_secret = join '', pairwise { $a ? '*' : $b } @mask, @secret;
		return ($masked_secret);
	}
	if ($u_type eq "id"){
		my $mask='XXXXXXXXXXXXXXX';
		my @mask=split( '', $mask );
		my @eid=split( '', $ec2_access_id );
        $masked_id = join '', pairwise { $a ? '*' : $b } @mask, @eid;
		return ($masked_id);
	}
}
sub _print_json {
    $j_out=shift;
    $json = JSON->new->allow_nonref or die "Error: $!\n";
    $json = $json->canonical(["true"]);
    $json = $json->allow_blessed(["true"]);
    $js= $json->pretty->encode( $j_out ) or die "Error: $!\n";
    print JSON_OUT $js;
}

sub _set_url {
# "switch" is part of perl core, but may be "fragile"
# if this doesn't work, comment out the switch stanza
# and then uncomment the "given" section as well as the "use feature/no warnings"
# "given" requires perl 5.10 or newer

    switch ($ec2_region) {
        case "ap-northeast-1"   { $ec2_url="http://ec2.ap-northeast-1.amazonaws.com" }
        case "ap-northeast-2"   { $ec2_url="http://ec2.ap-northeast-2.amazonaws.com" }
        case "ap-south-1"       { $ec2_url="http://ec2.ap-south-1.amazonaws.com" }
        case "ap-southeast-1"   { $ec2_url="http://ec2.ap-southeast-1.amazonaws.com" }
        case "ap-southeast-2"   { $ec2_url="http://ec2.ap-southeast-2.amazonaws.com" }
        case "ca-central-1"     { $ec2_url="http://ec2.ca-central-1.amazonaws.com" }
        case "eu-central-1"     { $ec2_url="http://ec2.eu-central-1.amazonaws.com" }
        case "eu-west-1"        { $ec2_url="http://ec2.eu-west-1.amazonaws.com" }
        case "eu-west-2"        { $ec2_url="http://ec2.eu-west-2.amazonaws.com" }
        case "sa-east-1"        { $ec2_url="http://ec2.sa-east-1.amazonaws.com" }
        case "us-east-1"        { $ec2_url="http://ec2.us-east-1.amazonaws.com" }
        case "us-east-2"        { $ec2_url="http://ec2.us-east-2.amazonaws.com" }
        case "us-west-1"        { $ec2_url="http://ec2.us-west-1.amazonaws.com" }
        case "us-west-2"        { $ec2_url="http://ec2.us-west-2.amazonaws.com" }
        else                    { $ec2_url="http://ec2.amazonaws.com" }
    }

#use feature qw/switch/;
#no warnings "experimental::smartmatch";

#    given($ec2_region) {
#        when (/ap-northeast-1/){ $ec2_url="http://ec2.ap-northeast-1.amazonaws.com"; }
#        when (/ap-northeast-2/){ $ec2_url="http://ec2.ap-northeast-2.amazonaws.com"; }
#        when (/ap-south-1/)    { $ec2_url="http://ec2.ap-south-1.amazonaws.com"; }
#        when (/ap-southeast-1/){ $ec2_url="http://ec2.ap-southeast-1.amazonaws.com"; }
#        when (/ap-southeast-2/){ $ec2_url="http://ec2.ap-southeast-2.amazonaws.com"; }
#        when (/ca-central-1/)  { $ec2_url="http://ec2.ca-central-1.amazonaws.com"; }
#        when (/eu-central-1/)  { $ec2_url="http://ec2.eu-central-1.amazonaws.com"; }
#        when (/eu-west-1/)     { $ec2_url="http://ec2.eu-west-1.amazonaws.com"; }
#        when (/eu-west-2/)     { $ec2_url="http://ec2.eu-west-2.amazonaws.com"; }
#        when (/sa-east-1/)     { $ec2_url="http://ec2.sa-east-1.amazonaws.com"; }
#        when (/us-east-1/)     { $ec2_url="http://ec2.us-east-1.amazonaws.com"; }
#        when (/us-east-2/)     { $ec2_url="http://ec2.us-east-2.amazonaws.com"; }
#        when (/us-west-1/)     { $ec2_url="http://ec2.us-west-1.amazonaws.com"; }
#        when (/us-west-2/)     { $ec2_url="http://ec2.us-west-2.amazonaws.com"; }
#        default                { $ec2_url="http://ec2.amazonaws.com"; }
#    }

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

    if ($missing){
		$EC="1";
		print colored ['red'],("!" x $sw);
        printf("\n\n\t\t%s\n\t\t%s\n\n", colored("Please specify the following options:",'red'),colored("$var",'yellow'));
		print colored ['red'],("!" x $sw);
		print "\n\n";
		_help;
        _myexit ($EC);
    }

    if (! $ec2_url) {
        _set_url;
    }
}

sub _get_opts {
	GetOptions(
    	'version'       	=>\$VERSION,
    	'config=s'          =>\@CONFIG_OPTIONS,
	 	'regions'	  		=>\$SHOW_REGIONS,
	 	'instances'			=>\$SHOW_INSTANCES,
	 	'ami'			    =>\$SHOW_AMI,
        'search=s'          =>\@SEARCHES,
        'output:s'          =>\@OUTPUT,
		'more'				=>\$MORE,
        ''                  =>\$MO,
        'help|?'        	=>\$HELP);

	if ($MO) {
        print "Invalid syntax given in options, please check your syntax\n\n";
        print "\t Command line was: \`$commandline\`\n\n";
        sleep(3);
    	_help;
        &_myexit;
    }

	if ($HELP) {
    	_help;
        &_myexit;
    }

    if ($MORE) {
    	_more_info;
        &_myexit;
    }

    &_check_vars;
	&_mask_it ("id");
	&_mask_it ("secret");

    if (@OUTPUT){
        foreach (@OUTPUT){
            $ot = lc $_;
			if (($ot eq "text") || ($ot eq "") || ($ot eq "t")) {
				$my_OFILE = $OFILE . ".txt";
				open(TXT,">>/tmp/$my_OFILE");
                $print_txt="true";
			} elsif (($ot eq "json") || ($ot eq "j")) {
				$my_OFILE = $OFILE . ".json";
				open(JSON_OUT,">>/tmp/$my_OFILE");
                %h_href=();
				$h_href{$OFILE}{INFO}{EC2}{"Access ID"}=$masked_id;
				$h_href{$OFILE}{INFO}{EC2}{"Secret Key"}=$masked_secret;
                $h_href{$OFILE}{INFO}{Execution}{Command}=$commandline;
                $h_href{$OFILE}{INFO}{EC2}{"Default Region"}=$ec2_region;
                $h_href{$OFILE}{INFO}{EC2}{"API Endpoint"}=$ec2_url;
                $h_href{$OFILE}{INFO}{Execution}{"User"}=$USER;
			} else {
				$EC="2";
				print "Invalid output method selected: only text or json supported\n";
				_myexit ($EC);
			}
        }
    }
    if (@CONFIG_OPTIONS) {
        foreach $c (@CONFIG_OPTIONS) {
            $c = lc $c;
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

    if ($SHOW_AMI){
        &_show_ami;
    }

    if (@SEARCHES) {
        print colored ['green'],"Gathering region info...\n\n";
        &_get_region_info;
        foreach $search (sort @SEARCHES) {
            ($type,$what)=split(/=/,$search);
            if ($type eq "instance"){
                $s_inst=$s_inst . ":" . $what;
                $si="true";
            } elsif ($type eq "name") {
                $s_name=$s_name . ":" . $what;
                $sn="true";
            } elsif ($type eq "type") {
                $s_type=$s_type . ":" . $what;
                $s_type = lc $s_type;
                $st="true";
            }elsif ($type eq "tag") {
                $s_tag=$s_tag . "::" . $what;
                $s_t="true";
            }elsif ($type eq "role") {
                $s_role=$s_role . ":" . $what;
                $s_r="true";
            }
        }
        if ($s_r){
            foreach ($s_role){
                my @values = split(/:/, $s_role);
                foreach my $ir (@values){
                    next if ($ir eq "");
                    print "Searching for role: $ir in all regions...\n";
                    if ($print_txt){printf TXT ("%s\n","Searching for role: $ir in all regions...");}
					foreach my $r (@r_name){
                    	&_search_iam_role($r,$ir);
						$count=scalar(@i);
                        if ($count lt "1"){
                            #print "\t$s not found in $r\n";
                        } else {
                            foreach (@i) {
                                printf("%s%s%s\n", "[", colored($_,'yellow'), "]");
                                if ($print_txt){printf TXT ("%s\n","[$_]");}
                                _show_instances($_,$r);
                            }
                        }
					}
                }
            }
        }
        if ($s_t){
            foreach ($s_tag){
                my @values = split(/::/, $s_tag);
                foreach my $s (@values){
                    next if ($s eq "");
                    ($t_key,$t_val)=split(/:/,$s);
                    print "Searching for tag: $t_key=>$t_val in all regions...\n";
                    if ($print_txt){printf TXT ("%s\n","Searching for tag: $t_key=>$t_val in all regions...");}
					foreach my $r (@r_name){
                    	&_search_instance_tag($t_key,$t_val,$r);
					}
                }
            }
        }
        if ($si){
            foreach ($s_inst){
                my @values = split(/:/, $s_inst);
                foreach my $s (@values){
                    next if ($s eq "");
                    print "Searching for instance \"$s\" in all regions...\n";
					if ($print_txt){printf TXT ("%s\n","Searching for instance \"$s\" in all regions...");}
                    foreach my $r (@r_name){
                        &_search_instances($r,$s);
                        $count=scalar(@i);
                        if ($count lt "1"){
                            #print "\t$s not found in $r\n";
                        } else {
		                    foreach (@i) {
                                printf("%s%s%s\n", "[", colored($_,'yellow'), "]");
								if ($print_txt){printf TXT ("%s\n","[$_]");}
        	                    _show_instances($_,$r);
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
					if ($print_txt){printf TXT ("%s\n","Searching for \"$s\" in all regions...");}
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
        if ($st){
            foreach ($s_type){
                my @values = split(/:/, $s_type);
                foreach my $t (@values){
                    next if ($t eq "");
                    print "Searching for \"$t\" instances in all regions...\n";
                    if ($print_txt){printf TXT ("%s\n","Searching for \"$t\ instances in all regions...");}
                    foreach my $r (@r_name){
                        &_search_types($r,$t);
                        $count=scalar(@i);
						if ($count lt "1"){
                            #print "type not found\n";
                        } else {
                            $found="true";
                            _show_types(@i);
                        }
                    }
                    if (! $found){
                        print "Sorry, no $t instances found\n\n";
                        if ($print_txt){printf TXT ("%s\n\n","Sorry, no $t instances found");}
                    }
                }
            }
        }
    }

    if ($SHOW_REGIONS) {
    	&_show_regions;
    }

    if ($SHOW_INSTANCES) {
        undef @i;
		&_get_instances;
		foreach (@i) {
        	printf("%s%s%s\n", "[", colored($_,'yellow'), "]");
			if ($print_txt){printf TXT ("%s\n","[$_]");}
        	_show_instances($_,$ec2_region);
    	}
    }

    if ($VERSION) {
        _version;
       _myexit;
    }

}

sub _search_instance_tag {
    $mykey=shift;
    $myval=shift;
    $my_ec2_region=shift;

    $ec2       = VM::EC2->new(-access_key => $ec2_access_id,-secret_key => $ec2_secret_key,-region=>$my_ec2_region,-endpoint => $ec2_url) or die "Error: $!\n";
    @tags = $ec2->describe_tags(-filter=> {'resource-type'=>'instance'});
    for my $t (@tags) {
        $id    = $t->resourceId;
        $key   = $t->key;
        $value = $t->value;

        if (($key eq $mykey) && ($value eq $myval)){
			&_search_instances($my_ec2_region,$id);
			$count=scalar(@i);
            if ($count lt "1"){
            	#print "\t$s not found in $r\n";
            } else {
            	foreach (@i) {
                	printf("%s%s%s\n", "[", colored($_,'yellow'), "]");
                    if ($print_txt){printf TXT ("%s\n","[$_]");}
                    _show_instances($_,$my_ec2_region);
                }
            }
        }
    }
}


sub _get_region_info {
    $ec2       = VM::EC2->new(-access_key => $ec2_access_id,-secret_key => $ec2_secret_key,-endpoint => $ec2_url) or die "Error: $!\n";
    @regions   = $ec2->describe_regions();
    foreach (sort @regions) {
        $name    = $_->regionName;
        push @r_name,$name;
    }
    $r_count=scalar(@regions);
    $h_href{$OFILE}{INFO}{Totals}{"Number of Regions found"}=$r_count;
    return (@r_name,@regions);
}

sub is_error {
    defined shift->error();
}

sub _show_ami_zone{
    $ec2_access_id = shift;
    $ec2_secret_key = shift;
    $my_ec2_region= shift;
    $imageowner = "self";
    $ec2a = VM::EC2->new(-access_key => $ec2_access_id,-secret_key => $ec2_secret_key,-region=>$my_ec2_region,-endpoint => $ec2_url);
    @AMI  = $ec2a->describe_images(-owner=>$imageowner);
    if (! @AMI) {
        printf("%-21s %-50s\n","    ","No AMIs found");
        if ($print_txt){printf TXT ("%-21s %-50s\n","    ","No AMIs found");}
        return;
    }
	foreach (sort @AMI){
        $OwnerID        = $_->imageOwnerId;
        $Desc           = $_->description;
        $State          = $_->imageState;
        $Name           = $_->name;
        $ImageType      = $_->imageType;
        $VirtType       = $_->virtualizationType;
        $RootDevType    = $_->rootDeviceType;
        $Public         = $_->isPublic;
        $Arc            = $_->architecture;
        $HV             = $_->hypervisor;
        $i_tags         = $_->tags;

        if ($Public){
            $Public = "True";
        } else {
            $Public = "False";
        }
		printf("%-21s %-50s\n","    ","$_");
        printf("%-26s %-50s\n","    ","Description: $Desc");
        printf("%-26s %-50s\n","    ","Architecture: $Arc");
        printf("%-26s %-50s\n","    ","Virtualization: $VirtType");
        printf("%-26s %-50s\n","    ","Root Device Type: $RootDevType");
        if ($print_txt){
            undef $s;
		    printf TXT ("%-21s %-50s\n","    ","$_");
            printf TXT ("%-26s %-50s\n","    ","Description: $Desc");
            printf TXT ("%-26s %-50s\n","    ","Architecture: $Arc");
            printf TXT ("%-26s %-50s\n","    ","Virtualization: $VirtType");
            printf TXT ("%-26s %-50s\n","    ","Root Device Type: $RootDevType");
        }
        $h_href{$OFILE}{REGIONS}{$my_ec2_region}{AMIs}{$_}{Description}=$Desc;
        $h_href{$OFILE}{REGIONS}{$my_ec2_region}{AMIs}{$_}{Architecture}=$Arc;
        $h_href{$OFILE}{REGIONS}{$my_ec2_region}{AMIs}{$_}{Virtualization}=$VirtType;
        $h_href{$OFILE}{REGIONS}{$my_ec2_region}{AMIs}{$_}{RootDevType}=$RootDevType;
        unless ( ! %$i_tags ){
				printf("%-26s %-50s\n", "    ","Tags:");
				if ($print_txt){printf TXT ("%-26s %-50s\n", "    ","Tags:");}
                foreach my $key (sort keys %$i_tags) {
                	$value = $i_tags->{$key};
                	printf("%-30s %-50s\n","    ","$key: $value");
                	if ($print_txt){printf TXT ("%-30s %-50s\n","    ","$key: $value");}
                    $h_href{$OFILE}{REGIONS}{$my_ec2_region}{AMIs}{$_}{Tags}{$key}=$value;
                }
        }
        print "\n";
        if ($print_txt){printf TXT (%s,"\n");}
    }
}

sub _show_ami {
    $imageowner = "self";
    print colored ['green'],"Gathering AMI info for $ec2_region...\n\n";
    if ($print_txt){printf TXT ("%s\n\n","Gathering AMI info for $ec2_region...");}
    $ec2       = VM::EC2->new(-access_key => $ec2_access_id,-secret_key => $ec2_secret_key,-endpoint => $ec2_url,-region=>$ec2_region);
    @AMI  = $ec2->describe_images(-owner=>$imageowner);
	unless (@AMI) {
		die "Error: ",$ec2->error if $ec2->is_error;
		print "No appropriate images found\n";
	}
    $a_count=scalar(@AMI);
    $h_href{$OFILE}{INFO}{Totals}{"Number of AMIs found"}=$a_count;
    foreach (sort @AMI){
        $OwnerID        = $_->imageOwnerId;
        $Desc           = $_->description;
        $State          = $_->imageState;
        $Name           = $_->name;
        $ImageType      = $_->imageType;
        $VirtType       = $_->virtualizationType;
        $RootDevType    = $_->rootDeviceType;
        $Public         = $_->isPublic;
        $Arc            = $_->architecture;
        $HV             = $_->hypervisor;
        $i_tags         = $_->tags;

        if ($Public){
            $Public = "True";
        } else {
            $Public = "False";
        }
        printf("%s%s%s\n", "[", colored("$_",'yellow'),"]");
    	printf("%-30s %-50s\n", colored("    Owner:",'blue'),$OwnerID);
    	printf("%-30s %-50s\n", colored("    Name:",'blue'),$Name);
    	printf("%-30s %-50s\n", colored("    Description:",'blue'),$Desc);
    	printf("%-30s %-50s\n", colored("    State:",'blue'),$State);
    	printf("%-30s %-50s\n", colored("    Image Type:",'blue'),$ImageType);
    	printf("%-30s %-50s\n", colored("    Architecture:",'blue'),$Arc);
    	printf("%-30s %-50s\n", colored("    Virtualization:",'blue'),$VirtType);
    	printf("%-30s %-50s\n", colored("    Hypervisor:",'blue'),$HV);
    	printf("%-30s %-50s\n", colored("    Root Device Type:",'blue'),$RootDevType);
    	printf("%-30s %-50s\n", colored("    Public:",'blue'),$Public);
        if ($print_txt){
            printf TXT ("%s\n", "[$_]");
    	    printf TXT ("%-30s %-50s\n","    Owner:",$OwnerID);
    	    printf TXT ("%-30s %-50s\n","    Name:",$Name);
    	    printf TXT ("%-30s %-50s\n","    Description:",$Desc);
    	    printf TXT ("%-30s %-50s\n","    State:",$State);
    	    printf TXT ("%-30s %-50s\n","    Image Type:",$ImageType);
    	    printf TXT ("%-30s %-50s\n","    Architecture:",$Arc);
    	    printf TXT ("%-30s %-50s\n","    Virtualization:",$VirtType);
    	    printf TXT ("%-30s %-50s\n","    Hypervisor:",$HV);
    	    printf TXT ("%-30s %-50s\n","    Root Device Type:",$RootDevType);
    	    printf TXT ("%-30s %-50s\n","    Public:",$Public);
        }
        $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Owner}=$OwnerID;
        $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Name}=$Name;
        $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Description}=$Desc;
        $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{State}=$State;
        $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{ImageType}=$ImageType;
        $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Architecture}=$Arc;
        $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Virtualization}=$VirtType;
        $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Hypervisor}=$HV;
        $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{RootDeviceType}=$RootDevType;
        $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Public}=$Public;
        unless ( ! %$i_tags ){
        	print colored ['blue'],"    Tags:\n";
        	if ($print_txt){ print TXT ("    Tags:\n");}
        	foreach my $key (sort keys %$i_tags) {
            	$value = $i_tags->{$key};
            	printf("%-21s %-50s\n","    ","$key: $value");
            	if ($print_txt){printf TXT ("%-21s %-50s\n","    ","$key: $value");}
                $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Tags}{$key}=$value;
        	}
    	}
       	print "\n";
       	if ($print_txt){ print TXT "\n";}
    }
}
sub _show_regions {
    &_get_region_info;
    print colored ['green'],"Gathering region info...\n\n";
	if ($print_txt){printf TXT ("%s\n\n","Gathering region info...");}
    foreach $r (sort @regions) {
        $name    = $r->regionName;
        $url     = $r->regionEndpoint;
        @zones   = $r->zones;
        printf("%s%s%s\n", "[", colored("$name",'yellow'),"]");
        printf("%-30s %-20s\n", colored("    Endpoint:",'blue'),$url);
        printf("%-30s\n", colored("    Zones:",'blue'));
        if ($print_txt){
		    printf TXT ("%s\n", "[$name]");
		    printf TXT ("%-30s %-20s\n","    Endpoint:",$url);
		    printf TXT ("%-30s\n","    Zones:");
    }
        $h_href{$OFILE}{REGIONS}{$r}{Endpoint}=$url;
        foreach $z (sort @zones) {
            printf("%-21s %-50s\n","    ",$z);
            push @{ $h_href{$OFILE}{REGIONS}{$name}{Zones}},"$z";
			if ($print_txt){printf TXT ("%-21s %-50s\n","    ",$z);}
        }
        $ec2 = VM::EC2->new(-access_key => $ec2_access_id,-secret_key => $ec2_secret_key,-region=>$name) or die "Error: $!\n";
        @vpc = $ec2->describe_vpcs();
		if (@vpc) {
			printf("%-30s\n", colored("    VPCs:",'blue'));
			if ($print_txt){printf TXT ("%-30s\n","    VPCs:");}
            foreach $v (sort @vpc){
				printf("%-21s %-50s\n","    ",$v);
                if ($print_txt){printf TXT ("%-21s %-50s\n","    ",$v);}
                $v = $ec2->describe_vpcs(-vpc_id=>$v);
                $tenancy = $v->instanceTenancy;
                $cidr    = $v->cidrBlock;
                $state   = $v->State;
                $v_tags  = $v->tags;
                if ($v_tags->{Name}){
                    $n=$v_tags->{Name};
                    printf("%-26s %-50s\n","    ","Name: $v_tags->{Name}");
                    if ($print_txt){printf TXT ("%-26s %-50s\n","    ","Name: $v_tags->{Name}");}
                }
                printf("%-26s %-50s\n","    ","CIDR Block: $cidr");
                printf("%-26s %-50s\n","    ","Tenancy: $tenancy");
                printf("%-26s %-50s\n\n","    ","State: $state");
                if ($print_txt){
                    printf TXT ("%-26s %-50s\n","    ","CIDR Block: $cidr");
                    printf TXT ("%-26s %-50s\n","    ","Tenancy: $tenancy");
                    printf TXT ("%-26s %-50s\n\n","    ","State: $state");
                }
                $h_href{$OFILE}{REGIONS}{$name}{VPCs}{$v}{$n}{CIDR}=$cidr;
                $h_href{$OFILE}{REGIONS}{$name}{VPCs}{$v}{$n}{Tenancy}="$tenancy";
                $h_href{$OFILE}{REGIONS}{$name}{VPCs}{$v}{$n}{State}="$state";
            }
		}
		printf("%-30s\n", colored("    AMIs:",'blue'));
		if ($print_txt){printf TXT ("%-30s\n","    AMIs:");}
		&_show_ami_zone ($ec2_access_id,$ec2_secret_key,$name);
        print "\n";
		if ($print_txt){printf TXT ("%s","\n");}
    }
    print "\n";
	if ($print_txt){printf TXT ("%s","\n");}
}

sub _search_hosts () {
    undef @i;
    undef @itags;
    undef @ti;
    $s_region=shift;
    $s_name=shift;
    @TAGS=('Name','Hostname');
    if ($s_region) {
        $my_ec2_region = $s_region;
    }else{
        $my_ec2_region = $ec2_region;
    }
	$ec2 = VM::EC2->new(-access_key => $ec2_access_id,-secret_key => $ec2_secret_key,-region=>$my_ec2_region,-endpoint => $ec2_url) or die "Error: $!\n";
    if ($s_name){
        foreach $tag (@TAGS){
            @ti = $ec2->describe_instances(-filter=>{'instance-state-name'=>['pending','running','shutting-down','stopping','stopped'],"tag:$tag"=> $s_name});
            push @itags, @ti;
        }
    } else {
		$EC="1";
        print "\t!!! Error: No name was specified\n";
        _myexit ($EC);
    }
    @i = do { my %seen; grep { !$seen{$_}++ } @itags };
    return @i;
}

sub _show_hosts {
    $h_count=scalar(@i);
    if ($h_total){
        $h_total= $h_total + $h_count;
    }else{
        $h_total=$h_count;
    }
    foreach $id (@i) {
        next if ($id eq "");
        printf("%s%s%s\n", "[", colored($id,'yellow'), "]");
        if ($print_txt){printf TXT ("%s\n", "[$id]");}
        _show_instances($id);
    }
}

sub _search_types () {
	$s_region=shift;
	$s_type=shift;
	if ($s_region) {
    	$my_ec2_region = $s_region;
    }else{
        $my_ec2_region = $ec2_region;
    }
    $ec2 = VM::EC2->new(-access_key => $ec2_access_id,-secret_key => $ec2_secret_key,-region=>$my_ec2_region,-endpoint => $ec2_url) or die "Error: $!\n";
	if ($s_type) {
		@i = $ec2->describe_instances(-filter=>{'instance-type'=>$s_type,'instance-state-name'=>['pending','running','shutting-down','stopping','stopped']});
	} else {
		$EC="1";
        print "\t!!! Error: No name was specified\n";
        _myexit ($EC);
    }
	return @i;
}

sub _show_types {
    $count=scalar(@i);
    $h_count=scalar(@i);
    if ($h_total){
        $h_total= $h_total + $h_count;
    }else{
        $h_total=$h_count;
    }
    print colored ['green'],"\n$count $s_type instances found in $s_region\n\n";
    if ($print_txt){print TXT "\n$count $s_type instances found in $s_region\n\n";}
	foreach $h (@i){
		next if ($h eq "");
		printf("%s%s%s\n", "[", colored($h,'yellow'), "]");
        if ($print_txt){printf TXT ("%s\n", "[$h]");}
        _show_instances($h);
	}
}

sub _search_iam_role () {
    $my_ec2_region=shift;
    $s_ir=shift;
    undef @i;
    $ec2 = VM::EC2->new(-access_key => $ec2_access_id,-secret_key => $ec2_secret_key,-region=>$my_ec2_region,-endpoint => $ec2_url) or die "Error: $!\n";
    #iam-instance-profile.arn,Values=*Sight*
    @i = $ec2->describe_instances(-filter=>{'instance-state-name'=>['pending','running','shutting-down','stopping','stopped'],'iam-instance-profile.arn'=>"*$s_ir*"});
    $h_count=scalar(@i);
    if ($h_total){
        $h_total= $h_total + $h_count;
    }else{
        $h_total=$h_count;
    }
    return @i;
}


sub _search_instances () {
    $s_region=shift;
    $s_id=shift;
    undef @i;
    if ($s_region) {
        $my_ec2_region = $s_region;
    }else{
        $my_ec2_region = $ec2_region;
    }
    $ec2 = VM::EC2->new(-access_key => $ec2_access_id,-secret_key => $ec2_secret_key,-region=>$my_ec2_region,-endpoint => $ec2_url) or die "Error: $!\n";
    if ($s_id){
        @i = $ec2->describe_instances(-instance_id=>$s_id,-filter=>{'instance-state-name'=>['pending','running','shutting-down','stopping','stopped']});
        @i = sort @i;
    } else {
        @i = $ec2->describe_instances(-filter=>{'instance-state-name'=>['pending','running','shutting-down','stopping','stopped']});
        @i = sort @i;
    }
    $h_count=scalar(@i);
    if ($h_total){
        $h_total= $h_total + $h_count;
    }else{
        $h_total=$h_count;
    }
    return @i;
}
sub _get_instances {
    &_search_instances;
    printf("%s %s...\n", colored("Getting list of instances in",'green'), colored($ec2_region,'cyan'));
    if ($print_txt){print TXT "Getting list of instances in $ec2_region\n";}
    $count=scalar(@i);
    if ($count lt "1"){
		$EC="1";
        print colored ['red'],"0 instances found, please verify your ID and Secret key if this is incorrect\n";
		if ($print_txt){print TXT "0 instances found, please verify your ID and Secret key if this is incorrect\n";}
        _myexit ($EC);
    }
    printf("%s %s %s %s\n\n",colored("Found",'green'),colored($count,'magenta'),colored("instances in",'green'),colored($ec2_region,'cyan'));
    if ($print_txt){printf TXT ("%s %s %s %s\n\n","Found",$count,"instances in",$ec2_region);}
}

sub _show_instances {
    $id=shift;
    $my_r=shift;
    $instance           = $ec2->describe_instances(-instance_id=>$id);
    $placement          = $instance->placement;
    $reservationId      = $instance->reservationId;
    $imageId            = $instance->imageId;
    $private_ip         = $instance->privateIpAddress;
    $public_ip          = $instance->ipAddress;
    $private_dns        = $instance->privateDnsName;
    $public_dns         = $instance->dnsName;
    $time               = $instance->launchTime;
    $status             = $instance->current_status;
    $vpc                = $instance->vpcId;
    $subnet             = $instance->subnetId;
    $type               = $instance->instanceType;
    $data               = $instance->userData;
    @groups             = $instance->groupSet;
    $tags               = $instance->tags;
    @devices            = $instance->blockDeviceMapping;
    $profile            = $instance->iamInstanceProfile;
    if ($profile){($cruft,$IAMrole)   = split(/\//,$profile->arn);}

    if ($tags){
        if ($tags->{Hostname}) {
            $NAME=$tags->{Hostname};
            printf("%-30s %-50s\n", colored("    Hostname",'blue'),$tags->{Hostname});
            if ($print_txt){printf TXT ("%-30s %-50s\n","    Hostname",$tags->{Hostname});}
        } elsif ($tags->{Name}) {
            $NAME=$tags->{Name};
    		printf("%-30s %-50s\n", colored("    Hostname",'blue'),$tags->{Name});
            if ($print_txt){printf TXT ("%-30s %-50s\n","    Hostname",$tags->{Name});}
		}
    }

    if ($vpc ne ""){
        $v = $ec2->describe_vpcs(-vpc_id=>$vpc);
        $v_tags  = $v->tags;
        if ($v_tags->{Name}){
            $vpc = $vpc . " ($v_tags->{Name})";
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
    if ($IAMrole){printf("%-30s %-50s\n", colored("    IAM Role:",'blue'),$IAMrole);}
    if ($print_txt){
        printf TXT ("%-30s %-50s\n", "    Instance Type:",$type);
        printf TXT ("%-30s %-50s\n", "    Zone:",$placement);
        printf TXT ("%-30s %-50s\n", "    VPC:",$vpc);
        printf TXT ("%-30s %-50s\n", "    Subnet:",$subnet);
        printf TXT ("%-30s %-50s\n", "    Reservation:",$reservationId);
        printf TXT ("%-30s %-50s\n", "    Image ID:",$imageId);
        printf TXT ("%-30s %-50s\n", "    Private IP:",$private_ip);
        printf TXT ("%-30s %-50s\n", "    Public IP:",$public_ip);
        printf TXT ("%-30s %-50s\n", "    Private Name:",$private_dns);
        printf TXT ("%-30s %-50s\n", "    Public Name:",$public_dns);
        printf TXT ("%-30s %-50s\n", "    Launch Time:",$time);
        printf TXT ("%-30s %-50s\n", "    State:",$status);
        if ($IAMrole){printf TXT ("%-30s %-50s\n","    IAM Role:",$IAMrole);}
    }
    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Name}=$NAME;
    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{InstanceType}=$type;
    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Zone}="$placement";
    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{VPC}=$vpc;
    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Subnet}=$subnet;
    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Reservation}=$reservationId;
    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{ImageId}=$imageId;
    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{PrivateIP}=$private_ip;
    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{PublicIP}=$public_ip;
    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{PrivateDNS}=$private_dns;
    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{PublicDNS}=$public_dns;
    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{LaunchTime}=$time;
    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{State}="$status";
    if ($IAMrole){$h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{IAMRole}="$IAMrole";}

    if (@devices){
        print colored ['blue'],"    Volumes:\n";
        if ($print_txt){print TXT "    Volumes:\n";}
        foreach $dev (@devices) {
            $devName   = $dev->deviceName;
            $volume    = $dev->volume;
            $delete    = $dev->deleteOnTermination;
			if ($delete eq "1"){$delete="True";}else{$delete="False";}
            @vols = $ec2->describe_volumes(-volume_id=>$volume);
            foreach $vol (@vols) {
                $vid    = $vol->volumeId;
                $size  = $vol->size;
                $snap  = $vol->snapshotId;
                $vzone  = $vol->availabilityZone;
                $vstatus = $vol->status;
                $ctime = $vol->createTime;
                $origin      = $vol->from_snapshot;
                $enc         = $vol->encrypted;
				$vtype		= $vol->volumeType;
				$iops		= $vol->iops;
                if ($enc){
                    $enc="True";
                }else{
                    $enc="False";
                }
                printf("%-21s %-50s\n","    ","$devName");
                printf("%-26s %-50s\n","    ","ID: $vid");
                printf("%-26s %-50s\n","    ","Type: $vtype");
                printf("%-26s %-50s\n","    ","Delete on Termination: $delete");
                printf("%-26s %-50s\n","    ","Size: $size GB");
                printf("%-26s %-50s\n","    ","IOPS: $iops");
                if ($snap){printf("%-26s %-50s\n","    ","Snap: $snap");}
                printf("%-26s %-50s\n","    ","Zone: $vzone");
                printf("%-26s %-50s\n","    ","Status: $vstatus");
                printf("%-26s %-50s\n","    ","Created: $ctime");
                if ($origin){printf("%-26s %-50s\n","    ","Origin: $origin");}
                printf("%-26s %-50s\n\n","    ","Encrypted: $enc");
			    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Volumes}{$devName}{ID}="$vid";
			    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Volumes}{$devName}{Type}="$vtype";
			    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Volumes}{$devName}{"Delete on Termination"}="$delete";
			    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Volumes}{$devName}{Size}="$size GB";
			    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Volumes}{$devName}{IOPS}="$iops";
			    if ($snap){$h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Volumes}{$devName}{Snap}="$snap";}
			    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Volumes}{$devName}{Zone}="$vzone";
			    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Volumes}{$devName}{Status}="$vstatus";
			    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Volumes}{$devName}{Created}="$ctime";
			    if ($origin){$h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Volumes}{$devName}{Origin}="$origin";}
			    $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Volumes}{$devName}{Encrypted}="$enc";
                if ($print_txt){
                    printf TXT ("%-21s %-50s\n","    ","$devName");
                    printf TXT ("%-26s %-50s\n","    ","ID: $vid");
                    printf TXT ("%-26s %-50s\n","    ","Type: $vtype");
                    printf TXT ("%-26s %-50s\n","    ","Delete on Termination: $delete");
                    printf TXT ("%-26s %-50s\n","    ","Size: $size GB");
                    printf TXT ("%-26s %-50s\n","    ","IOPS: $iops");
                    if ($snap){printf TXT ("%-26s %-50s\n","    ","Snap: $snap");}
                    printf TXT ("%-26s %-50s\n","    ","Zone: $vzone");
                    printf TXT ("%-26s %-50s\n","    ","Status: $vstatus");
                    printf TXT ("%-26s %-50s\n","    ","Created: $ctime");
                    if ($origin){printf TXT ("%-26s %-50s\n","    ","Origin: $origin");}
                    printf TXT ("%-26s %-50s\n\n","    ","Encrypted: $enc");
                }
            }
        }

    }

    if ($data){
        print colored ['blue'],"    User Data:\n";
        if ($print_txt){print TXT "    User Data:\n";}
        @lines = split /\n/, $data;
        foreach $line (sort @lines) {
            printf("%-21s %-50s\n","    ",$line);
            if ($print_txt){printf TXT ("%-21s %-50s\n","    ",$line);}
            push @{ $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{UserData}},$line;
        }
        print "\n";
		if ($print_txt){print TXT "\n";}
    }
    if ($tags){
        print colored ['blue'],"    Tags:\n";
        if ($print_txt){print TXT "    Tags:\n";}
		foreach my $key (sort keys %$tags) {
    		$value = $tags->{$key};
    		printf("%-21s %-50s\n","    ","$key: $value");
            if ($print_txt){printf TXT ("%-21s %-50s\n","    ","$key: $value");}
            $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{Tags}{$key}=$value;
		}
        print "\n";
		if ($print_txt){print TXT "\n";}

    }
    if (@groups){
        print colored ['blue'],"    Security Groups:\n";
        if ($print_txt){print TXT "    Security Groups:\n";}
	    for $g (sort @groups){
		    $gid		= $g->groupId;
		    $gname		= $g->groupName;
		    $sg 		= $ec2->describe_security_groups($g);
		    @gperms_i		= $sg->ipPermissions;
		    @gperms_e		= $sg->ipPermissionsEgress;
			printf("%-21s %-50s\n","    ","$gname");
			printf("%-26s %-50s\n","    ","ID: $gid");
            if ($print_txt){
			    printf TXT ("%-21s %-50s\n","    ","$gname");
			    printf TXT ("%-26s %-50s\n","    ","ID: $gid");
            }
			if (@gperms_i) {
				printf("%-26s %-50s\n","    ","Ingress Rules:");
				if ($print_txt){printf TXT ("%-26s %-50s\n","    ","Ingress Rules:");}
				for $i (@gperms_i) {
         			$protocol = $i->ipProtocol;
         			$fromPort = $i->fromPort;
         			$toPort   = $i->toPort;
         			@ranges   = $i->ipRanges;
					next if ($protocol eq "-1");
					printf("%-30s %-50s\n","    ","$protocol from: $fromPort to: $toPort");
					if ($print_txt){printf TXT ("%-30s %-50s\n","    ","$protocol from: $fromPort to: $toPort");}
					for $r (sort @ranges) {
						printf("%-35s %-50s\n","    ","Source IP: $r");
						if ($print_txt){printf TXT ("%-35s %-50s\n","    ","Source IP: $r");}
                        push @{ $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{SecurityGroups}{$gid}{$gname}{IngressRules}{$protocol}{"Ports and Source IP"}},"from: $fromPort to: $toPort  $r";
					}
      			}
			}
			if (@gperms_e){
				printf("%-26s %-50s\n\n","    ","Egress Rules:");
				if ($print_txt){printf TXT ("%-26s %-50s\n\n","    ","Egress Rules:");}
				for $j (@gperms_e) {
         			$protocol = $j->ipProtocol;
         			$fromPort = $j->fromPort;
         			$toPort   = $j->toPort;
         			@ranges   = $j->ipRanges;
					next if ($protocol eq "-1");
					printf("%-30s %-50s\n","    ","$protocol from: $fromPort to: $toPort");
					if ($print_txt){printf TXT ("%-30s %-50s\n","    ","$protocol from: $fromPort to: $toPort");}
					for $r (sort @ranges) {
						printf("%-35s %-50s\n","    ","Destination IP: $r");
						if ($print_txt){printf TXT ("%-35s %-50s\n","    ","Destination IP: $r");}
                        push @{ $h_href{$OFILE}{REGIONS}{$my_r}{Instances}{$id}{SecurityGroups}{$gid}{$gname}{EgressRules}{$protocol}{"Ports and Source IP"}},"from: $fromPort to: $toPort  $r";
					}
      			}
			}
	    }
    }
    print "\n";
	if ($print_txt){print TXT "\n";}
}

sub _sec_convert {
    $total_sec=shift;
    $secs=$total_sec%60;
    $mins=($total_sec/60)%60;
    $hours=($total_sec/(60*60))%24;
    $days=int($total_sec/(24*60*60));
    if ($days){$run_time= "$days day ";}
    if ($hours){$run_time="$run_time" . "$hours hours ";}
    if ($mins){$run_time="$run_time" . "$mins minutes ";}
    if ($secs){$run_time="$run_time" . "$secs seconds";}
    return($run_time);
}

sub _myexit{
	$EC=shift;
	if ($EC eq "2") {
        unlink "/tmp/$OFILE.*";
	}
    chomp($end=`date`);
    $es=time();
    $run_secs = $es - $ss;
    &_sec_convert($run_secs);
	print "\n";
	print colored ['cyan'],("=" x $sw);
	print "\n";
	if ($h_total){print "Total Instances found: $h_total\n";}
	if ($r_count){print "Total Regions found: $r_count\n";}
	if ($a_count){print "Total AMIs found: $a_count\n";}
	print "Execution Start: $start\n";
	print "Execution End: $end\n";
	print "Execution Time: $run_time\n\n";
	print "Command: $commandline\n";
	print "User: $USER\n";
	print "AWS Access ID: $masked_id\n";
	print "AWS Secet Key: $masked_secret\n";
	print "AWS Region: $ec2_region\n";
	print "AWS API URL: $ec2_url\n";
	if ( @OUTPUT && $EC ne "2" ) {
		foreach (@OUTPUT) {
			if (($_ eq "text") || ($_ eq "") || ($_ eq "t")) {
				$myOFILE=$OFILE . ".txt";
              	print TXT "\n==============================================================\n";
              	if ($h_total){print TXT "Total Instances found: $h_total\n";}
              	if ($r_count){print TXT "Total Regions found: $r_count\n";}
              	if ($a_count){print TXT "Total AMIs found: $a_count\n";}
              	print TXT "Execution Start: $start\n";
              	print TXT "Execution End: $end\n";
              	print TXT "Execution Time: $run_time\n\n";
              	print TXT "Command: $commandline\n";
              	print TXT "User: $USER\n";
              	print TXT "AWS Access ID: $masked_id\n";
              	print TXT "AWS Secet Key: $masked_secret\n";
              	print TXT "AWS Region: $ec2_region\n";
              	print TXT "AWS API URL: $ec2_url\n";
				close($myOFILE);
				push @files,"/tmp/$myOFILE";
			} elsif (($_ eq "json") || ($_ eq "j")) {
				$myOFILE=$OFILE . ".json";
                if ($h_total){$h_href{$OFILE}{INFO}{Totals}{"Total Instances found"}=$h_total;}
                $h_href{$OFILE}{INFO}{Execution}{Start}=$start;
                $h_href{$OFILE}{INFO}{Execution}{End}=$end;
                $h_href{$OFILE}{INFO}{Execution}{Time}="$run_time";
                &_print_json(\%h_href);
                close($myOFILE);
				push @files,"/tmp/$myOFILE";
			}
		}
        print "\n";
        print colored ['cyan'],("=" x $sw);
		print "\n\nOutput written to:\n";
		foreach (@files){
			print colored ['yellow'],"\t$_\n";
		}
		print "\n";
	}
	exit $EC;
}

## Main
$SIG {"TERM"} = \&_term_exit;
$SIG {"HUP"} = \&_term_exit;
$SIG {"INT"} = \&_int_exit;

print "\033[2J";    #clear the screen

if (! $ARGV[0]) {
	$EC="1";
    _help;
    exit 1;
}

# process options and gather/display results in _get_opts
$commandline = join " ", $0, @ARGV;
chomp($start=`date`);
$ss=time();
_get_opts;

# cleanup and exit
_myexit 0;
