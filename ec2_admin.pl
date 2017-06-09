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
    @MODULES=("Getopt::Long","JSON","Term::ANSIColor","VM::EC2");
    foreach $m (@MODULES) {eval("use $m");if ($@) {die "\n\t!!! Error: $m module not found!!!\n\n\tPlease install the $m perl module:\n\t\'perl -MCPAN -e 'install $m\' or \'cpan $m\'\n\n";}}
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

sub _more_info {
    _version;
    print qq|
    * Short options can be given as well: "-i" instead of --instances, etc

    * Users can set environment variables or use "--conf <opt=val>" to specify EC2 options
        export EC2_SECRET_KEY=<aws secret key id>
        export EC2_ACCESS_KEY=<aws access id>
        export EC2_REGION=<aws region to query>
        export EC2_URL=<API endpoint to use>

    "--config <opt=val>" will override environment variables


    * Multiple "--search" options can be specified, user can mix types:
        "$PROGNAME -s name=host1.mydomain.com -s inst=i-237f8d --search name=test1"

    * Searches will take place in all regions, for both names and instances.  Results will
        be shown and then the next search request will be processed.  Only non-terminated
        instances will be searched for and shown.

    *  Only hostname searches will wildcard searches (*<name>*) so the more
        exact the name entered, the more precise the results.  Searches are case
        sensitive.

    * Multiple "--output" formats can be selected

    To do:
        * Ability to create {instances,vpcs,?}
        * Control instances (stop, start, terminate)
        * Fix JSON output
            Instance State/Zone are null
        * Search by:
            State (running, terminated, etc)
            Tags (tag:value)
        * Optimize and remove duplication
            * do region lookup once and store instead of calling for every command
            * breakout any duplicated routines (search, etc)
        * Typo checks, general cleanup (remove extra comments, etc)
        * ?


|;
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

sub _print_json {
    $j_out=shift;
    $json = JSON->new->allow_nonref or die "Error: $!\n";
    $json = $json->canonical(["true"]);
    $json = $json->allow_blessed(["true"]);
    $js= $json->pretty->encode( $j_out ) or die "Error: $!\n";
    print JSON_OUT $js;
}

sub _print_txt{
	$out_info=shift;
    foreach $t (@OUTPUT){
        $t = lc $t;
        if (($t eq "") || ($t eq "text") || ($t eq "t")){
	        print TXT ($out_info);
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

    if (@OUTPUT){
        $output="true";
        foreach (@OUTPUT){
            $ot = lc $_;
			if (($ot eq "text") || ($ot eq "") || ($ot eq "t")) {
				$my_OFILE = $OFILE . ".txt";
				open(TXT,">>/tmp/$my_OFILE");
			} elsif (($ot eq "json") || ($ot eq "j")) {
				$my_OFILE = $OFILE . ".json";
				open(JSON_OUT,">>/tmp/$my_OFILE");
                %h_href=();
                push @{ $h_href{$OFILE}{Command}},$commandline;
                push @{ $h_href{$OFILE}{EC2}{"Access ID"}},$ec2_access_id;
                push @{ $h_href{$OFILE}{EC2}{"Secret Key"}},$ec2_secret_key;
                push @{ $h_href{$OFILE}{EC2}{Region}},$ec2_region;
                push @{ $h_href{$OFILE}{EC2}{"API Endpoint"}},$ec2_url;
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
		&_print_txt ("Gathering region info...\n\n");
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
            }
        }
        if ($si){
            foreach ($s_inst){
                my @values = split(/:/, $s_inst);
                foreach my $s (@values){
                    next if ($s eq "");
                    print "Searching for instance \"$s\" in all regions...\n";
					&_print_txt ("Searching for instance \"$s\" in all regions...\n");
                    foreach my $r (@r_name){
                        &_search_instances($r,$s);
                        $count=scalar(@i);
                        if ($count lt "1"){
                            #print "\t$s not found in $r\n";
                        } else {
		                    foreach (@i) {
                                printf("%s%s%s\n", "[", colored($_,'yellow'), "]");
								&_print_txt ("[$_]\n");
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
					&_print_txt ("Searching for \"$s\" in all regions...\n");
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
                    &_print_txt ("Searching for \"$t\ instances in all regions...\n");
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
                        &_print_txt ("Sorry, no $t instances found\n\n");
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
			&_print_txt ("[$_]\n");
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
        &_print_txt ("\t\tNo AMIs found\n");
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
        printf("%-26s %-50s\n", "    ","Description: $Desc");
        printf("%-26s %-50s\n", "    ","Architecture: $Arc");
        printf("%-26s %-50s\n", "    ","Virtualization: $VirtType");
        printf("%-26s %-50s\n", "    ","Root Device Type: $RootDevType");
        &_print_txt ("\t\t$_\n");
        &_print_txt ("\t\t   Description: $Desc\n");
        &_print_txt ("\t\t   Architecture: $Arc\n");
        &_print_txt ("\t\t   Virtualization: $VirtType\n");
        &_print_txt ("\t\t   Root Device Type: $RootDevType\n");
        push @{ $h_href{$OFILE}{Regions}{$my_ec2_region}{AMIs}{$_}{Description}},$Desc;
        push @{ $h_href{$OFILE}{Regions}{$my_ec2_region}{AMIs}{$_}{Architecture}},$Arc;
        push @{ $h_href{$OFILE}{Regions}{$my_ec2_region}{AMIs}{$_}{Virtualization}},$VirtType;
        push @{ $h_href{$OFILE}{Regions}{$my_ec2_region}{AMIs}{$_}{RootDevType}},$RootDevType;
        unless ( ! %$i_tags ){
				printf("%-26s %-50s\n", "    ","Tags:");
                &_print_txt ("\t\t   Tags:\n");
                foreach my $key (sort keys %$i_tags) {
                	$value = $i_tags->{$key};
                	printf("%-30s %-50s\n","    ","$key: $value");
                	&_print_txt ("\t\t\t$key: $value\n");
                    push @{ $h_href{$OFILE}{Regions}{$my_ec2_region}{AMIs}{$_}{Tags}{$key}},$value;
                }
        }
        print "\n";
        &_print_txt ("\n");
    }
}

sub _show_ami {
    $imageowner = "self";
    print colored ['green'],"Gathering AMI info for $ec2_region...\n\n";
    &_print_txt ("Gathering AMI info for $ec2_region...\n\n");
    $ec2       = VM::EC2->new(-access_key => $ec2_access_id,-secret_key => $ec2_secret_key,-endpoint => $ec2_url,-region=>$ec2_region);
    @AMI  = $ec2->describe_images(-owner=>$imageowner);
	unless (@AMI) {
		die "Error: ",$ec2->error if $ec2->is_error;
		print "No appropriate images found\n";
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
        &_print_txt ("[$_]\n");
    	&_print_txt ("\tOwner: $OwnerID\n");
    	&_print_txt ("\tName: $Name\n");
    	&_print_txt ("\tDescription:\ $Desc\n");
    	&_print_txt ("\tState: $State\n");
    	&_print_txt ("\tImage Type: $ImageType\n");
    	&_print_txt ("\tArchitecture: $Arc\n");
    	&_print_txt ("\tVirtualization: $VirtType\n");
    	&_print_txt ("\tHypervisor: $HV\n");
    	&_print_txt ("\tRoot Device Type: $RootDevType\n");
    	&_print_txt ("\tPublic: $Public\n");
        push @{ $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Owner}},$OwnerID;
        push @{ $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Name}},$Name;
        push @{ $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Description}},$Desc;
        push @{ $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{State}},$State;
        push @{ $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{ImageType}},$ImageType;
        push @{ $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Architecture}},$Arc;
        push @{ $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Virtualization}},$VirtType;
        push @{ $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Hypervisor}},$HV;
        push @{ $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{RootDeviceType}},$RootDevType;
        push @{ $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Public}},$Public;
        unless ( ! %$i_tags ){
        	print colored ['blue'],"    Tags:\n";
        	&_print_txt ("\tTags:\n");
        	foreach my $key (sort keys %$i_tags) {
            	$value = $i_tags->{$key};
            	printf("%-21s %-50s\n","    ","$key: $value");
            	&_print_txt ("\t   $key: $value\n");
                push @{ $h_href{$OFILE}{AMIs}{$ec2_region}{$_}{Tags}{$key}},$value;
        	}
    	}
       	print "\n";
       	&_print_txt ("\n");
    }
}
sub _show_regions {
    &_get_region_info;
    print colored ['green'],"Gathering region info...\n\n";
	&_print_txt ("Gathering region info...\n\n");
    foreach $r (sort @regions) {
        $name    = $r->regionName;
        $url     = $r->regionEndpoint;
        @zones   = $r->zones;
        printf("%s%s%s\n", "[", colored("$name",'yellow'),"]");
        printf("%-30s %-20s\n", colored("    Endpoint:",'blue'),$url);
        printf("%-30s\n", colored("    Zones:",'blue'));
		&_print_txt ("[$name]\n");
		&_print_txt ("\tEndpoint: $url\n");
		&_print_txt ("\tZones:\n");
        push @{ $h_href{$OFILE}{Regions}{$r}{Endpoint}},$url;
        $empty="";
        foreach $z (sort @zones) {
            printf("%-21s %-50s\n","    ",$z);
            push @{ $h_href{$OFILE}{Regions}{$name}{Zones}->{$z}},$empty;
			&_print_txt ("\t\t$z\n");
        }
        $ec2 = VM::EC2->new(-access_key => $ec2_access_id,-secret_key => $ec2_secret_key,-region=>$name) or die "Error: $!\n";
        @vpc = $ec2->describe_vpcs();
		if (@vpc) {
			printf("%-30s\n", colored("    VPCs:",'blue'));
			&_print_txt ("\tVPCs:\n");
            foreach $v (sort @vpc){
				printf("%-21s %-50s\n","    ",$v);
                &_print_txt ("\t\t$v\n");
                $v = $ec2->describe_vpcs(-vpc_id=>$v);
                $tenancy = $v->instanceTenancy;
                $cidr    = $v->cidrBlock;
                $state   = $v->State;
                $v_tags  = $v->tags;
                if ($v_tags->{Name}){
                    $n=$v_tags->{Name};
                    printf("%-26s %-50s\n","    ","Name: $v_tags->{Name}");
                    &_print_txt ("\t\t   Name: $v_tags->{Name}\n");
                }
                printf("%-26s %-50s\n","    ","CIDR Block: $cidr");
                printf("%-26s %-50s\n","    ","Tenancy: $tenancy");
                printf("%-26s %-50s\n\n","    ","State: $state");
                &_print_txt ("\t\t   CIDR Block: $cidr\n");
                &_print_txt ("\t\t   Tenancy: $tenancy\n");
                &_print_txt ("\t\t   State: $state\n\n");
                push @{ $h_href{$OFILE}{Regions}{$name}{VPCs}{$v}{$n}{CIDR}},$cidr;
                push @{ $h_href{$OFILE}{Regions}{$name}{VPCs}{$v}{$n}{Tenancy}},$tenancy;
                push @{ $h_href{$OFILE}{Regions}{$name}{VPCs}{$v}{$n}{State}},$state;
            }
		}
		printf("%-30s\n", colored("    AMIs:",'blue'));
        &_print_txt ("\tAMIs:\n");
		&_show_ami_zone ($ec2_access_id,$ec2_secret_key,$name);
        print "\n";
		&_print_txt ("\n");
    }
    print "\n";
	&_print_txt ("\n");
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
    foreach $id (@i) {
        next if ($id eq "");
        printf("%s%s%s\n", "[", colored($id,'yellow'), "]");
		&_print_txt ("[$id]\n");
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
    print colored ['green'],"\n$count $s_type instances found in $s_region\n\n";
    &_print_txt ("\n$count $s_type instances found in $s_region\n\n");
	foreach $h (@i){
		next if ($h eq "");
		printf("%s%s%s\n", "[", colored($h,'yellow'), "]");
        &_print_txt ("[$h]\n");
        _show_instances($h);
	}
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
    return @i;
}
sub _get_instances {
    &_search_instances;
    printf("%s %s...\n", colored("Getting list of instances in",'green'), colored($ec2_region,'cyan'));
	&_print_txt ("Getting list of instances in $ec2_region\n");
    $count=scalar(@i);
    if ($count lt "1"){
		$EC="1";
        print colored ['red'],"0 instances found, please verify your ID and Secret key if this is incorrect\n";
		&_print_txt ("0 instances found, please verify your ID and Secret key if this is incorrect\n");
        _myexit ($EC);
    }
    printf("%s %s %s %s\n\n",colored("Found",'green'),colored($count,'magenta'),colored("instances in",'green'),colored($ec2_region,'cyan'));
	&_print_txt ("Found $count instances in $ec2_region\n\n");
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
        if ($tags->{Hostname}) {
            $NAME=$tags->{Hostname};
            printf("%-30s %-50s\n", colored("    Hostname",'blue'),$tags->{Hostname});
            &_print_txt ("\tHostname:\t$tags->{Hostname}\n");
        } elsif ($tags->{Name}) {
            $NAME=$tags->{Name};
    		printf("%-30s %-50s\n", colored("    Hostname",'blue'),$tags->{Name});
			&_print_txt ("\tHostname:\t$tags->{Name}\n");
		}
    }

    $v = $ec2->describe_vpcs(-vpc_id=>$vpc);
    $v_tags  = $v->tags;
    if ($v_tags->{Name}){
        if ( $vpc ne ""){
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
	&_print_txt ("\tInstance Type:\t$type\n");
	&_print_txt ("\tZone:\t\t$placement\n");
	&_print_txt ("\tVPC:\t\t$vpc\n");
	&_print_txt ("\tSubnet:\t\t$subnet\n");
	&_print_txt ("\tReservation:\t$reservationId\n");
	&_print_txt ("\tImage ID:\t$imageId\n");
	&_print_txt ("\tPrivate IP:\t$private_ip\n");
	&_print_txt ("\tPublic IP:\t$public_ip\n");
	&_print_txt ("\tPrivate Name:\t$private_dns\n");
	&_print_txt ("\tPublic Name:\t$public_dns\n");
	&_print_txt ("\tLaunch Time:\t$time\n");
	&_print_txt ("\tState:\t\t$status\n");
    push @{ $h_href{$OFILE}{Instances}{$id}{Name}},$NAME;
    push @{ $h_href{$OFILE}{Instances}{$id}{InstanceType}},$type;
    push @{ $h_href{$OFILE}{Instances}{$id}{Region}},$ec2_region;
    push @{ $h_href{$OFILE}{Instances}{$id}{Zone}},$placement;
    push @{ $h_href{$OFILE}{Instances}{$id}{VPC}},$vpc;
    push @{ $h_href{$OFILE}{Instances}{$id}{Subnet}},$subnet;
    push @{ $h_href{$OFILE}{Instances}{$id}{Reservation}},$reservationId;
    push @{ $h_href{$OFILE}{Instances}{$id}{ImageId}},$imageId;
    push @{ $h_href{$OFILE}{Instances}{$id}{PrivateIP}},$private_ip;
    push @{ $h_href{$OFILE}{Instances}{$id}{PublicIP}},$public_ip;
    push @{ $h_href{$OFILE}{Instances}{$id}{PrivateDNS}},$private_dns;
    push @{ $h_href{$OFILE}{Instances}{$id}{PublicDNS}},$public_dns;
    push @{ $h_href{$OFILE}{Instances}{$id}{LaunchTime}},$time;
    push @{ $h_href{$OFILE}{Instances}{$id}{State}},$status;
    if ($data){
        print colored ['blue'],"    User Data:\n";
		&_print_txt ("\tUser Data:\n");
        @lines = split /\n/, $data;
        foreach $line (sort @lines) {
            printf("%-21s %-50s\n","    ",$line);
			&_print_txt ("\t\t\t$line\n");
            push @{ $h_href{$OFILE}{Instances}{$id}{UserData}},$line;
        }
        print "\n";
		&_print_txt ("\n");
    }
    if ($tags){
        print colored ['blue'],"    Tags:\n";
		&_print_txt ("\tTags:\n");
		foreach my $key (sort keys %$tags) {
    		$value = $tags->{$key};
    		printf("%-21s %-50s\n","    ","$key: $value");
			&_print_txt ("\t\t\t$key: $value\n");
            push @{ $h_href{$OFILE}{Instances}{$id}{Tags}{$key}},$value;
		}
        print "\n";
		&_print_txt ("\n");

    }
    if (@groups){
        print colored ['blue'],"    Security Groups:\n";
		&_print_txt ("\tSecurity Groups:\n");
	    for $g (sort @groups){
		    $gid		= $g->groupId;
		    $gname		= $g->groupName;
		    $sg 		= $ec2->describe_security_groups($g);
		    @gperms_i		= $sg->ipPermissions;
		    @gperms_e		= $sg->ipPermissionsEgress;
			printf("%-21s %-50s\n","    ","ID: $gid");
			printf("%-26s %-50s\n","    ","Name: $gname");
			&_print_txt ("\t\t\tID: $gid\n");
			&_print_txt ("\t\t\t\tName: $gname\n");
			if (@gperms_i) {
				printf("%-26s %-50s\n","    ","Ingress Rules:");
				&_print_txt ("\t\t\t\tIngress Rules:\n");
				for $i (@gperms_i) {
         			$protocol = $i->ipProtocol;
         			$fromPort = $i->fromPort;
         			$toPort   = $i->toPort;
         			@ranges   = $i->ipRanges;
					next if ($protocol eq "-1");
					printf("%-30s %-50s\n","    ","$protocol from: $fromPort to: $toPort");
					&_print_txt ("\t\t\t\t\t$protocol from: $fromPort to: $toPort\n");
					for $r (sort @ranges) {
						printf("%-35s %-50s\n","    ","Source IP: $r");
						&_print_txt ("\t\t\t\t\t\tSource IP: $r\n");
                        push @{ $h_href{$OFILE}{Instances}{$id}{SecurityGroups}{$gid}{$gname}{IngressRules}{$protocol}{"Ports and Source IP"}},"from: $fromPort to: $toPort  $r";
					}
      			}
			}
			if (@gperms_e){
				printf("%-26s %-50s\n\n","    ","Egress Rules:");
				&_print_txt ("\t\t\t\tEgress Rules:\n\n");
				for $j (@gperms_e) {
         			$protocol = $j->ipProtocol;
         			$fromPort = $j->fromPort;
         			$toPort   = $j->toPort;
         			@ranges   = $j->ipRanges;
					next if ($protocol eq "-1");
					printf("%-30s %-50s\n","    ","$protocol from: $fromPort to: $toPort");
					&_print_txt ("\t\t\t\t\t$protocol from: $fromPort to: $toPort\n");
					for $r (sort @ranges) {
						printf("%-35s %-50s\n","    ","Destination IP: $r");
						&_print_txt ("\t\t\t\t\t\tDestination IP: $r\n");
                        push @{ $h_href{$OFILE}{Instances}{$id}{SecurityGroups}{$gid}{$gname}{EgressRules}{$protocol}{"Ports and Source IP"}},"from: $fromPort to: $toPort  $r";
					}
      			}
			}
	    }
    }
    print "\n";
	&_print_txt ("\n");
}

sub _myexit{
	$EC=shift;
	if ($EC eq "2") {
		system("rm -f /tmp/$OFILE.*");
	}
	if ( @OUTPUT && $EC ne "2" ) {
		foreach (@OUTPUT) {
			if (($_ eq "text") || ($_ eq "") || ($_ eq "t")) {
				$myOFILE=$OFILE . ".txt";
				close($myOFILE);
				push @files,"/tmp/$myOFILE";
			} elsif (($_ eq "json") || ($_ eq "j")) {
				$myOFILE=$OFILE . ".json";
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

system("clear");

if (! $ARGV[0]) {
	$EC="1";
    _help;
    _myexit ($EC);
}

# process options and gather/display results in _get_opts
$commandline = join " ", $0, @ARGV;
_get_opts;

# cleanup and exit
_myexit 0;
