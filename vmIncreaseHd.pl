#!/usr/bin/perl -w  
###############################################################################  
# Author: Sebastien Courtois
# Email: secourtois8678 [ at ] gmail.com
#  
# Created: 29/02/2016
#  
# Abstract:  
# Increase VM HD capacity (add) in VMware -- Space increase unit in Go
#  
# Script requires VMware's PERL SDK (aka vCLI)therefore it must be placed  
# in apropriate directory tree location to work correctly.  
# Optimal location is at /usr/lib/vmware-vcli/apps/vm  
#  
# Disclaimer: Use this script at your own risk. Author is not responsible  
# for any impacts of using this script.  
# vmIncreaseHd.pl
###############################################################################  
use strict;  
use warnings;  
use FindBin;  
use lib "$FindBin::Bin/../";  
use VMware::VIRuntime;  
use XML::LibXML;  
use AppUtil::VMUtil;  
use AppUtil::XMLInputUtil;  
#use Data::Dumper;  
$Util::script_version = "1.0";  
my %opts = (  
    'vmname' => {  
	type => "=s",  
	help => "Name of virtual machine",  
	required => 1,  
    },  
    'growhdgo' => {  
	type => "=i",  
	help => "How many Go you want to grow up your HD",  
	required => 0,  
    },  
    'hardisk' => {  
	type => "=s",  
	help => "Name of hardDisk to grow up",  
	required => 1,  
    },  
    );  
Opts::add_options(%opts);  
Opts::parse();  
Opts::validate(\&validate);  
# connect to the server  
Util::connect();  
my $vmname = Opts::get_option('vmname');  
my $growhdgo = Opts::get_option('growhdgo');  
my $hardisk = Opts::get_option('hardisk');  
&vm_Increase_HD('vmname' => $vmname,  
	       'growHdGo' => $growhdgo,  
	       'hardisk' => $hardisk);  
Util::disconnect();  
exit;  
# just a little fonction to tranform Go (human readable) en Ko (unit HD space in vmware)
sub go_in_ko {
    my %params = @_;
    my $valInGo = $params{valInGo};
    my $valInKo = 0;
    $valInKo = $valInGo * 1024 * 1024;
    
    return $valInKo;
}

sub vm_Increase_HD {  
    my %params = @_;  
    my $vmname =$params{vmname};  
    my $growHdGo =$params{growHdGo};  
    my $hardisk = $params{hardisk};  
    my $vm_view;  
    $vm_view = Vim::find_entity_view(view_type => 'VirtualMachine',  
				     filter => {'name' => $vmname });  
    if(!defined $vm_view) {  
	print "Cannot find VM: $vmname\n";  
	return(255);  
    }  
    my $devices = $vm_view->config->hardware->device;  
    foreach my $dev (@$devices) { # DEVICE  
	my $device_type = ref($dev);  
	my $device_name = $dev->deviceInfo->label;  
	my $device_key = $dev->key;  
	my $idDeviceRezo="";

	if ( $device_type =~ m/VirtualDisk/ ) { # VirtualDisk
	    my $summary = $dev->deviceInfo->summary;
	    my $hdCapacity = $dev->capacityInKB;
	    my $hdKey = $dev->key;
	    my $device_backing=$dev->backing;
#	    print $device_name."\n";
#	    print $hardisk."\n";
	    my $newValHdKo=0;
	    my $growHdKo=0;
	    $growHdKo=go_in_ko('valInGo' => $growHdGo );

	    if ( $device_name =~ /$hardisk/ ) {
		$newValHdKo=$growHdKo + $hdCapacity;
		print "Device type HD : $device_type\n";  
		print "HD capacity : $hdCapacity\n";
		print "HD Label : $device_name\n";
		print "HD Summary : $summary\n";
		print "HD key : $hdKey\n";
		print "Grow HD in Go : $growHdGo\n";
		print $device_backing."\n";
		my $changed_device;  
		$changed_device = VirtualDisk->new(capacityInKB => $newValHdKo,
						 backing => $dev->backing,
						 deviceInfo => $dev->deviceInfo,
						 controllerKey => $dev->controllerKey,
						 key => $hdKey,
						 unitNumber => $dev->unitNumber);
					      
		my $config_spec_operation;
		$config_spec_operation = VirtualDeviceConfigSpecOperation->new('edit');
		my $device_spec =VirtualDeviceConfigSpec->new(operation => $config_spec_operation, device => $changed_device);  

		my @device_config_specs = ();  
		push(@device_config_specs, $device_spec);  
		my $vmspec = VirtualMachineConfigSpec->new(deviceChange => \@device_config_specs);  
            # RECONFIGURE VM  
		eval {  
		    print "Changing HD capacity $device_name in virtual machine $vmname\n";  
		    $vm_view->ReconfigVM( spec => $vmspec );  
		    print "Success\n";  
		};  
		if ($@) {  
		    print "Reconfiguration failed:\n";  
		    print($@);  
		}  
		

	    }
	} # VirtualDisk - END
    } # DEVICES - END  
    return;  
}  
sub validate {  
    my $valid = 1;  
    return $valid;  
}  


