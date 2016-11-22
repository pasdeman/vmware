#!/usr/bin/perl -w  
###############################################################################  
# take a look at this link : https://github.com/lamw/vghetto-scripts/tree/master/perl
#
# Author: Sebastien Courtois
#
# Created: 04/12/2015  
#  
# Abstract:  
# Move a vm in the right resourcePool 
#  
# Script requires VMware's PERL SDK (aka vCLI)therefore it must be placed  
# in apropriate directory tree location to work correctly.  
# Optimal location is at /usr/lib/vmware-vcli/apps/vm  
#  
# Disclaimer: Use this script at your own risk. Author is not responsible  
# for any impacts of using this script.  
# vmchgpool.pl --server=vcenter.your.domain.com --datacenter=yourDC --clusterEsx=targetCluster --resourcePoolN0=resourcePoolLevel0 --resourcePoolN1=childFirstGenerationRP 
###############################################################################  

use strict;
use warnings;
use VMware::VIRuntime;
use VMware::VILib;
use Data::Dumper;
$Util::script_version = "1.0";  

my %opts = (
    datacenter => {
	type => "=s",
        help => "DataCenter (ex: Infrastructure nationale)",
        required => 1,
    },
    clusterEsx => {
        type => "=s",
        help => "Cluster Esx (ex: ESX_SIG, etc.)",
        required => 1,
    },
    resourcePoolN0 => {
	type => "=s",
	help => "ResourcePool Niveau 0 (ex: prod,preprod,Test-Dev, etc.)",
	required => 1,
    },
    resourcePoolN1 => {
	type => "=s",
	help => "ResourcePool Niveau 1 (ex: Veeam-linux, Veeam-window, etc.)",
	required => 0,
    },
    vmname => {
	type => "=s",
	help => "nom de la vm a deplacer",
	required => 1,
    },
    );
Opts::add_options(%opts);

Opts::parse();
Opts::validate();
Util::connect();


# Obtain all inventory objects of the specified type
my $resourcePoolN1 = "";
my $datacenter = Opts::get_option('datacenter');
my $clusterEsx = Opts::get_option('clusterEsx'); 
my $resourcePoolN0 = Opts::get_option('resourcePoolN0');
my $myVmname = Opts::get_option('vmname');
$resourcePoolN1 = Opts::get_option('resourcePoolN1');

my $myIdTargetResourcePool = "";
my %rp_idVsName = ();

my $datacenter_view = Vim::find_entity_view(view_type => 'Datacenter',
					    filter => { name => $datacenter });
if (!$datacenter_view) {
    die "Datacenter '" . $datacenter . "' not found\n";
}

my $clusterComputeResource_views = Vim::find_entity_views(view_type => 'ClusterComputeResource',
					begin_entity => $datacenter_view,
                                        filter => {name => $clusterEsx});



foreach my $clusterResource_view (@$clusterComputeResource_views) {
    my $my_clusterName = $clusterResource_view->name;
    # alimentation du tableau de hash contenant name/id des sous pool pour le cluster esx courant
    my $sousPool_views =  Vim::find_entity_views(view_type => 'ResourcePool',
						 begin_entity => $clusterResource_view);
    foreach my $sousPool_view (@$sousPool_views) {
	my $myCrtNameRp = $sousPool_view->name;
	my $myCrtValueRp = $sousPool_view->config->entity->value;
	$rp_idVsName{$myCrtValueRp} = $myCrtNameRp;
        #Util::trace(0, "\t==> les petits enfants : $titi ----- $tutu\n");
    }
    
    # pour deboggage 
#    foreach my $k (keys(%rp_idVsName)) {
#	print "---Clef=$k ---Valeur=$rp_idVsName{$k}\n";
#    }
#    while( my ($k,$v) = each(%rp_idVsName) ) {
#	print ">>>Clef=$k ----Valeur=$v\n";
#    }


    # recherche des sous pool (child) de pool de ressource N0 (prod / preprod / etc.)
    my $entity_views = Vim::find_entity_views(view_type => 'ResourcePool',
					begin_entity => $clusterResource_view,
	                                filter => {name => $resourcePoolN0});
#	print "\n****************************\n";
#	print Dumper($entity_views)."\n";
#	print "\n****************************\n";

    foreach my $entity_view (@$entity_views) {    
	my $entity_name = $entity_view->name;
	my $entity_value = $entity_view->config->entity->value;
	my $entity_ParentValue = $entity_view->parent->value;
	my $childId_views = $entity_view->resourcePool;
	Util::trace(0, "===> Datacenter : $datacenter\n"); 
	Util::trace(0, "\t--> ClusterName: $my_clusterName\n"); 
	Util::trace(0, "\t\t--> RessourcePoolName: $entity_name - idRessourcePool: $entity_value - ParentId RP: $entity_ParentValue\n");
	if (( !defined $resourcePoolN1 ) || ( $resourcePoolN1 eq "" )) {
	    $myIdTargetResourcePool = $entity_value;
	} else {
	    foreach my $child_view (@$childId_views) {
		# apparement pour unbless une propriete multivalué, il faut dans le foreach faire un (@$myvar)
		my $current_view = $child_view->value  ;
		if( exists( $rp_idVsName{$current_view} ) ) {
		    print "";
		    if ( $rp_idVsName{$current_view} =~ /$resourcePoolN1/ ) {
			$myIdTargetResourcePool = $current_view;
			Util::trace(0, "\t\t\t==> Sous Pool : $current_view ----- $rp_idVsName{$current_view} \n");
		    }
		}
	    }
	} 
	
  }
#	print "\n****************************\n";
#	print Dumper($entity_views)."\n";
#	print "\n****************************\n";

}

&vm_change_ressourcePool('vmname' => $myVmname,  
	       'idtargetpool' => $myIdTargetResourcePool,
               'mortype' => 'ResourcePool' );


# Disconnect from the server
Util::disconnect();


sub vm_change_ressourcePool {  
    my %params = @_;  
    my $vmname =$params{vmname};  
    my $idTargetPool = $params{idtargetpool}; 
    my $mor_type = $params{mortype};
    my $vm_view;  
    $vm_view = Vim::find_entity_view(view_type => 'VirtualMachine',  
				     filter => {'name' => $vmname });  
    if(!defined $vm_view) {  
	print "Cannot find VM: $vmname\n";  
	return(255);  
    }  
    #print Dumper($vm_view)."\n";
    my $resourceP = ManagedObjectReference->new(type => 'ResourcePool', value => $idTargetPool);

#    print Dumper($resourceP);
#    print "**************************\n";
    # RelocateSpec 
    my $vmspec = VirtualMachineRelocateSpec->new(pool => $resourceP);

#   print Dumper($vmspec);
    
    # RECONFIGURE VM  
    eval {  
	print "Moving vm $vmname to correct resourcepool \n";  
	$vm_view->RelocateVM_Task(spec => $vmspec );  
	print "Success\n";  
    };  
    if ($@) {  
	print "Reconfiguration failed:\n";  
	print($@);  
    }  
    
    return;  
}  
sub validate {  
    my $valid = 1;  
    return $valid;  
}  


exit;  
