use LWP::UserAgent;
use MIME::Base64::Perl;
use XML::Simple;
use Text::CSV;
use Log::Log4perl qw(:easy);
use Data::Dumper;
BEGIN { $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0 }

my $supporturl="See https://discdungeon.cdw.com/vvtwiki/index.php/PatchMonkey for more info.\n";

## Set up logging
if ($debug eq "") {$debug='0';}
Log::Log4perl->easy_init( 
	{ level   => $debug,
	  file    => ">>PatchMonkey.log" } );
	  
# Check for input file
if ($ARGV[0] eq "") {die "No input file specified. $supporturl";}
if ($ARGV[0] eq "status" && $ARGV[1] ne "") {print "Running in Status Mode\n"; $statusmode=1;$myfile=$ARGV[1];} else {print "Running in Patch Mode\n"; $statusmode=0;$myfile=$ARGV[0];}

# Open input file and loop through
open my $fh, "<", $myfile or die "myfile: $!";
my $csv = Text::CSV->new ({ binary => 1, auto_diag => 1, sep_char => "\t" });
$csv->column_names ($csv->getline ($fh));
my $totalservers = 0;
my $stagesuccess = 0;
my $applysuccess = 0;
while ( not $csv->eof ) {
	my $row = $csv->getline_hr($fh);
	# clean up blank rows
	next unless grep $_, %$row;
	$totalservers++;
	# check for required columns in input file.
	if ($statusmode==0 && ($row->{server} eq "" || $row->{user} eq "" || $row->{password} eq "" || $row->{file} eq "" || $row->{sftpserver} eq "" || $row->{sftpuser} eq "" || $row->{sftppassword} eq "" || $row->{path} eq "")) { 
		print &logtime . "\tRequired fields not in input file\n\n$supporturl";
		next;
	} elsif ($statusmode==1 && ($row->{server} eq "" || $row->{user} eq "" || $row->{password} eq "")) {
		print &logtime . "\tRequired fields not in input file\n\n$supporturl";
		next;
	} elsif ($statusmode==1) {
		# everything looks good for status - lets run it!
		$status = &logtime . "\tQuerying Server $row->{server}\n";
		print $status;
		DEBUG($status);
#### Active Options Info ####
		$returninfo=&getOptions($row->{server},$row->{user},$row->{password},"Active");
		# Lets parse out our return
		$message = $returninfo->{result};
		$options = $returninfo->{options};
		$status = &logtime . "\t$row->{server}\tActive Options Query: " . &responsedictionary($message) . "\n";
		foreach (@$options) {
			$option = $_->{displayName};
			if ($option eq "") {$option="None";}
			$status=$status . &logtime . "\t$row->{server}\tActive Options: $option\n";
		}
		print $status;
		DEBUG($status);
#### Inactive Options Info ####
		$returninfo=&getOptions($row->{server},$row->{user},$row->{password},"Inactive");
		# Lets parse out our return
		$message = $returninfo->{result};
		$options = $returninfo->{options};
		$status = &logtime . "\t$row->{server}\tInactive Options Query: " . &responsedictionary($message) . "\n";
		foreach (@$options) {
			$option = $_->{displayName};
			if ($option eq "") {$option="None";}
			$status=$status . &logtime . "\t$row->{server}\tInactive Options: $option\n";
		}
		print $status;
		DEBUG($status);
#### Version info ####
		$returninfo=&getVersion($row->{server},$row->{user},$row->{password},"Active");
		# Lets parse out our return
		$message = $returninfo->{result};
		$version = $returninfo->{version};
		$status = &logtime . "\t$row->{server}\tActive Version Query: " . &responsedictionary($message) . "\n";
		$status=$status . &logtime . "\t$row->{server}\tActive Version: $version\n";
		print $status;
		DEBUG($status);
		$returninfo=&getVersion($row->{server},$row->{user},$row->{password},"Inactive");
		# Lets parse out our return
		$message = $returninfo->{result};
		$version = $returninfo->{version};
		$versioncheck = scalar %version;
		if ($versioncheck == 0) {$version = "None";}
		$status = &logtime . "\t$row->{server}\tInactive Version Query: " . &responsedictionary($message) . "\n";
		$status=$status . &logtime . "\t$row->{server}\tInactive Version: $version\n";
		print $status;
		DEBUG($status);
	} else {
		# everything looks good - lets try to apply the patch
		$stage = &logtime . "\tStaging patch $row->{method} $row->{path} $row->{file} for $row->{server}\n";
		print $stage;
		DEBUG($stage);
		$returninfo=&stagepatch($row->{server},$row->{user},$row->{password},$row->{sftpserver},$row->{path},$row->{file},$row->{sftpuser},$row->{sftppassword},$row->{method});
		# Lets parse out our return
		$error = $returninfo->{remoteMessages}->{error};
		$warning = $returninfo->{remoteMessages}->{warning};
		$info = $returninfo->{remoteMessages}->{info};
		$message = $returninfo->{remoteMessages}->{messageKey};
		DEBUG(Dumper $returninfo);
		if ($error eq "true") {
			$stage = &logtime . "\t\tResult: Problem with staging patch - " . &responsedictionary($message) . "\n";
			print $stage;
			DEBUG($stage);
			print &logtime . "\t\tSee log file for more information\n";
		} elsif ($warning eq "true") {
			$stagesuccess++;
			$stage = &logtime . "\t\tResult: Staging patch successful with warnings - " . &responsedictionary($message) . "\n";
			print $stage;
			DEBUG($stage);
			print &logtime . "\t\tSee log file for more information\n";
		} elsif ($info eq "true") {
			$stagesuccess++;
			$stage = &logtime . "\t\tResult: Staging patch successful - " . &responsedictionary($message) . "\n";
			print $stage;
			DEBUG($stage);
		} else {
			$stage = &logtime . "\t\tUnexpected result. See log file for more information.\n";
			print $stage;
			DEBUG($stage);
		}
		if ($returninfo->{remoteMessages}->{error} eq "false") {
			print &logtime . "\t   Applying patch for " . $row->{server} . "\n";
			$returninfo=&applypatch($row->{server},$row->{user},$row->{password});
			my ($error, $warning, $info, $message);
			if (ref $returninfo->{remoteMessages} eq 'ARRAY') {
				$arraylist = $returninfo->{remoteMessages};
				foreach (@$arraylist) {
					#print Dumper $_;
					if ($_->{error} eq "true") {
						$error = $_->{error};
						$message = $_->{messageKey};
						last;
					} elsif ($_->{warning} eq "true") {
						$warning = $_->{warning};
						$message = $_->{messageKey};
						last;
					} else {
						$info = $_->{info};
						$message = $->{messageKey};
					}
				}
			} else {
				$error = $returninfo->{remoteMessages}->{error};
				$warning = $returninfo->{remoteMessages}->{warning};
				$info = $returninfo->{remoteMessages}->{info};
				$message = $returninfo->{remoteMessages}->{messageKey};
			}
			DEBUG(Dumper $returninfo);
			if ($error eq "true") {
				$stage = &logtime . "\t\tResult: Problem with applying patch - " . &responsedictionary($message) . "\n";
				print $stage;
				DEBUG($stage);
				print &logtime . "\t\tSee log file for more information\n";
			} elsif ($warning eq "true") {
				$applysuccess++;
				$stage = &logtime . "\t\tResult: Applying patch successful with warnings - " . &responsedictionary($message) . "\n";
				print $stage;
				DEBUG($stage);
				print &logtime . "\t\tSee log file for more information\n";
			} elsif ($info eq "true") {
				$applysuccess++;
				$stage = &logtime . "\t\tResult: Applying patch successful - " . &responsedictionary($message) . "\n";
				print $stage;
				DEBUG($stage);
			} else {
				$stage = &logtime . "\t\tUnexpected result. See log file for more information.\n";
				print $stage;
				DEBUG($stage);
			}
		}
	}
}
close $fh;
if ($statusmode==0) {$status = "\n" . &logtime . "\tFinal Results:\n\t\t\tTotal Servers:$totalservers\n\t\t\tStage Successful:$stagesuccess\n\t\t\tApply Successful:$applysuccess\n";}
if ($statusmode==1) {$status = &logtime . "\tRun Complete\n";}
print $status;
DEBUG($status);

if (!($totalservers eq $applysuccess) && $statusmode==0) {
	print "\t\t\tNot all servers completed successfully.\n";
	exit 1;
} else {
	exit 0;
}

sub stagepatch {
	my ($server,$user,$password,$sftpserver,$path,$file,$sftpuser,$sftppassword,$method) = @_;
	$authstring ="$user:$password";
	$encodedauth = encode_base64($authstring);

	$xml='<?xml version="1.0" encoding="UTF-8"?>
	<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
		<SOAP-ENV:Header xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">
			<wsa:Action>urn:prepareRemoteUpgrade</wsa:Action>
			<wsa:MessageID>uuid:88042ed4-0c17-4aba-acfe-f6c68c1c6f0c</wsa:MessageID>
		  <wsa:ReplyTo>
			 <wsa:Address>http://www.w3.org/2005/08/addressing/anonymous</wsa:Address>
		  </wsa:ReplyTo>
			<wsa:To>https://server/platform-services/services/PrepareRemoteUpgradeService.PrepareRemoteUpgradeServiceHttpSoap11Endpoint</wsa:To>
		</SOAP-ENV:Header>
		<SOAP-ENV:Body>
			<prepareRemoteUpgrade xmlns="http://services.api.platform.vos.cisco.com">
				<args0>
					<name xmlns:ns7="http://server_url/xsd">' . $file . '</name>
					<path xmlns:ns8="http://server_url/xsd">' . $path . '</path>
					<password xmlns:ns12="http://server_url/xsd">' . $sftppassword . '</password>
					<server xmlns:ns16="http://server_url/xsd">' . $sftpserver . '</server>
					<upgradeLocation xmlns:ns18="http://server_url/xsd">upgradefile.location.remote.' . $method . '</upgradeLocation>
					<upgradeType xmlns:ns19="http://server_url/xsd">patch</upgradeType>
					<user xmlns:ns20="http://server_url/xsd">' . $sftpuser . '</user>
				</args0>
				<args1>pm123</args1>
				<args2>false</args2>
			</prepareRemoteUpgrade>
		</SOAP-ENV:Body>
	</SOAP-ENV:Envelope>';
	
#####'

	$url = "https://$server:8443/platform-services/services/PrepareRemoteUpgradeService.PrepareRemoteUpgradeServiceHttpsSoap11Endpoint/";			
	$cmua = new LWP::UserAgent;
	$request = new HTTP::Request('POST', $url );

	$request->header( Authorization => "Basic $encodedauth",'Content-Type' => 'text/xml; charset=utf-8' );

	$request->content( $xml );
	$response = $cmua->request($request);
	$$response_text = $response->content;

	$cleanedxml = &cleanxml($$response_text);
	DEBUG($cleanedxml);
	$xml = new XML::Simple;
	$data = $xml->XMLin($cleanedxml);
	$return = $data->{prepareRemoteUpgradeResponse}->{return};
	return $return;
}

sub applypatch {
	my ($server,$user,$password) = @_;
	$authstring ="$user:$password";
	$encodedauth = encode_base64($authstring);

	$xml='<?xml version="1.0" encoding="UTF-8"?>
	<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
		<SOAP-ENV:Header xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">
			<wsa:Action>urn:startUpgrade</wsa:Action>
			<wsa:MessageID>uuid:88042ed4-0c17-4aba-acfe-f6c68c1c6f11</wsa:MessageID>
		  <wsa:ReplyTo>
			 <wsa:Address>http://www.w3.org/2005/08/addressing/anonymous</wsa:Address>
		  </wsa:ReplyTo>
			<wsa:To>https://server/platform-services/services/StartUpgradeService.StartUpgradeServiceHttpSoap11Endpoint</wsa:To>
		</SOAP-ENV:Header>
		<SOAP-ENV:Body>
			<startUpgrade xmlns="http://services.api.platform.vos.cisco.com">
				<args0>pm123</args0>
				<args1>false</args1>
				<args2>false</args2>
			</startUpgrade>
		</SOAP-ENV:Body>
	</SOAP-ENV:Envelope>';
	$url = "https://$server:8443/platform-services/services/StartUpgradeService.StartUpgradeServiceHttpsSoap11Endpoint/";
	$cmua = new LWP::UserAgent;
	$request = new HTTP::Request('POST', $url );

	$request->header( Authorization => "Basic $encodedauth",'Content-Type' => 'text/xml; charset=utf-8' );
### '
	$request->content( $xml );
	$response = $cmua->request($request);
	$$response_text = $response->content;
	
	$cleanedxml = &cleanxml($$response_text);
	DEBUG($cleanedxml);
	$xml = new XML::Simple;
	$data = $xml->XMLin($cleanedxml);
	$return = $data->{startUpgradeResponse}->{return};
	return $return;
}

sub getOptions {
	my ($server,$user,$password,$active) = @_;
	$authstring ="$user:$password";
	$encodedauth = encode_base64($authstring);

	$xml='<?xml version="1.0" encoding="UTF-8"?>
	<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
		<SOAP-ENV:Header xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">
			<wsa:Action>urn:get' . $active . 'Options</wsa:Action>
			<wsa:MessageID>uuid:88042ed4-0c17-4aba-acfe-f6c68c1c6f0c</wsa:MessageID>
		  <wsa:ReplyTo>
			 <wsa:Address>http://www.w3.org/2005/08/addressing/anonymous</wsa:Address>
		  </wsa:ReplyTo>
			<wsa:To>https://server/platform-services/services/OptionsService.OptionsServiceHttpsSoap11Endpoint</wsa:To>
		</SOAP-ENV:Header>
		<SOAP-ENV:Body>
			<get' . $active . 'Options xmlns="http://services.api.platform.vos.cisco.com"/>
		</SOAP-ENV:Body>
	</SOAP-ENV:Envelope>';

	$url = "https://$server:8443/platform-services/services/OptionsService/";
	$cmua = new LWP::UserAgent;
	$request = new HTTP::Request('POST', $url );

	$request->header( Authorization => "Basic $encodedauth",'Content-Type' => 'text/xml; charset=utf-8' );
	$request->content( $xml );
	$response = $cmua->request($request);
	$$response_text = $response->content;

	$cleanedxml = &cleanxml($$response_text);
	DEBUG($cleanedxml);
	$xml = new XML::Simple;
	$data = $xml->XMLin($cleanedxml,ForceArray => [ 'options' ]);
	$getOptionsResponse = "get" . $active . "OptionsResponse";
	$return = $data->{$getOptionsResponse}->{return};
	return $return;
}

sub getVersion {
	my ($server,$user,$password,$active) = @_;
	$authstring ="$user:$password";
	$encodedauth = encode_base64($authstring);

	$xml='<?xml version="1.0" encoding="UTF-8"?>
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <soapenv:Header>
        <wsa:Action xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">urn:get' . $active . 'Version</wsa:Action>
        <wsa:MessageID xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">uuid:7481e8cf-ba47-49dc-9566-b52596fd4444</wsa:MessageID>
        <wsa:ReplyTo xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">
            <wsa:Address>http://www.w3.org/2005/08/addressing/anonymous</wsa:Address>
        </wsa:ReplyTo>
        <wsa:To xmlns:wsa="http://schemas.xmlsoap.org/ws/2004/08/addressing">https://' .  $server . '/platform-services/services/VersionService.VersionServiceHttpSoap11Endpoint</wsa:To>
    </soapenv:Header>
    <soapenv:Body>
        <get' . $active . 'Version xmlns="http://services.api.platform.vos.cisco.com"/>
    </soapenv:Body>
</soapenv:Envelope>';
	
#####'

	$url = "https://$server:8443/platform-services/services/VersionService/";
	$cmua = new LWP::UserAgent;
	$request = new HTTP::Request('POST', $url );

	$request->header( Authorization => "Basic $encodedauth",'Content-Type' => 'text/xml; charset=utf-8' );

	$request->content( $xml );
	$response = $cmua->request($request);
	$$response_text = $response->content;

	$cleanedxml = &cleanxml($$response_text);
	DEBUG($cleanedxml);
	$xml = new XML::Simple;
	$data = $xml->XMLin($cleanedxml);
	$getVersionResponse = "get" . $active . "VersionResponse";
	$return = $data->{$getVersionResponse}->{return};
	return $return;
}

sub responsedictionary {
	my ($response) = @_;
	my $nodots = $response;
	$nodots=~s/\.//g;
$responselookup{errorcmdfailure}="The requested command returned the indicated result code. Non zero results indicate a failure.";
$responselookup{errorcmdprimarynode}="The requested action is not permitted on the first node (Publisher).";
$responselookup{errorcmdsecondarynode}="The requested action is not permitted on a subsequent node (Subscriber).";
$responselookup{errordirectorynotaccessible}="The indicated directory could not accessed.";
$responselookup{errorproductnotdetermined}="The product information was not accessible. Please review the Cisco Unified Communications OS Platform API logs.";
$responselookup{errorremotethrottled}="Error when the request was denied due to throttling.";
$responselookup{errorsinstallfileisonotvalid}="The selected ISO file is not valid. This indicates that the download of the ISO file corrupted the file or the ISO file on the remote server is corrupt.";
$responselookup{errorsinstallfileisorenamed}="Upgrade has detected that the ISO file name has been changed from the original name. This is not allowed.";
$responselookup{errorsinstallfilemd5failed}="The checksum could not be calculated.";
$responselookup{errorsinstallfilenotvalid}="The selected file is not valid.";
$responselookup{errorsinstallfileunpack}="The selected ISO file is not valid. Possible reasons are the file was corrupted on download or the file is corrupted on the remote server.";
$responselookup{errorsoapinternal}="Error when a SOAP service experiences an unexpected problem.";
$responselookup{errorsswitchgrub}="The machine could not switch to the inactive version. Please verify the inactive version was properly installed.";
$responselookup{errorsswitchlicensing_grace_period}="Switch Version is not allowed during Licensing Grace Period.";
$responselookup{errorsswitchreboot}="The machine successfully switch to the inactive version however the reboot failed.";
$responselookup{errorsswitchsync}="The machine could not sync the inactive version to the active version. Please verify the inactive version was properly installed and try again.";
$responselookup{errorsswitchsynclock}="The machine could not obtain a sync lock. Please verify the inactive version was properly installed and try again.";
$responselookup{errorssystem}="An unknown error occurred while accessing the upgrade file.";
$responselookup{errorsupgradebadpassword}="The user name or password is not valid.";
$responselookup{errorsupgradechecksumfailed}="Checksum of file failed. Upgrade patch may be corrupted or tampered with. Please verify.";
$responselookup{errorsupgradeconnectionHWDisallowed}="This server is not supported for use with the version of Cisco Unity Connection that you are trying to install. For information on supported servers, see the applicable version of the Cisco Unity Connection Supported Platforms List at http://www.cisco.com/en/US/products/ps6509/products_data_sheets_list.html ";
$responselookup{errorsupgradecopfileDisallowed}="Copfile candidates found in the patch directory are not allowed by the current version";
$responselookup{errorsupgradecopyfailed}="Copy of file failed. Upgrade patch may be corrupted or tampered with. Please verify.";
$responselookup{errorsupgradecopyvendorlinksfailed}="Copy of VendorLinks failed. Upgrade patch may be corrupted or tampered with. Please verify.";
$responselookup{errorsupgradedirectorynotfound}="The directory could not be located.";
$responselookup{errorsupgradediskspace}="There is not enough disk space in the common partition to perform the upgrade. Please use either the Platform Command Line Interface or the Real-Time Monitoring Tool (RTMT) to free space on the common partition.";
$responselookup{errorsupgradefilenotdownloaded}="The file could not be downloaded.";
$responselookup{errorsupgradefilenotfound}="The file could not be located.";
$responselookup{errorsupgradefirstnodeissue}="Connectivity Issue to First Node. Verify that the first node is powered on, the network connection is up and the security password on this node and the first node are the same.";
$responselookup{errorsupgradefromVersionDisallowed}="The selected upgrade is disallowed from the current version";
$responselookup{errorsupgradeHardwareUnsupported}="This hardware is no longer supported.";
$responselookup{errorsupgradeHWNoDeploymentsSupported}="This upgrade software no longer supports this hardware for the installed deployment.";
$responselookup{errorsupgradeincompatibleftp}="The ftp server used is incompatible with the local client. Please upgrade to a newer version or reattempt using sftp.";
$responselookup{errorsupgradeincompatiblesftp}="The sftp server used is incompatible with the local client. Please upgrade to a newer version or reattempt using ftp.";
$responselookup{errorsupgradelicensing_grace_period}="Upgrades are prohibited during Licensing Grace Period.";
$responselookup{errorsupgrademediaisofile}="The media contains an iso data file, not an iso image.";
$responselookup{errorsupgrademissingchecksum}="The Checksum file is missing. Upgrade patch may be corrupted or tampered with. Please verify.";
$responselookup{errorsupgrademountfailed}="Unable to mount the local file system. This could be caused by a corrupt ISO file. For example, FTPing the ISO file to the remote server in ascii mode would cause this error.";
$responselookup{errorsupgradenodeployment}="Unable to determine the install deployment type which is required for upgrade. Please refer to upgrade log for further information.";
$responselookup{errorsupgradenofileordirectory}="The file or directory could not be located.";
$responselookup{errorsupgradePreflight}="The preflight script in the upgrade file failed. Please review the install logs for more information.";
$responselookup{errorsupgraderemoteunavail}="The remote file could not be accessed or fully downloaded. Please verify the file permissions or check the remote server's status.";
$responselookup{errorsupgradesourcefilenotfound}="Source file doesn't exist. Upgrade patch may be corrupted or tampered with. Please verify.";
$responselookup{errorsupgradesubnoValid}="No valid upgrades found. The first node (publisher) must be upgraded before upgrading this node.";
$responselookup{errorsupgradesubpubnotavailable}="The first node (publisher) is not currently available. Access to the publisher is required for this operation.";
$responselookup{errorsupgradesubpubwrongunrest}="Restricted/Unrestricted software mismatch. Publisher and subsequent node (Subscriber) must be running same software type (restricted vs. unrestricted).";
$responselookup{errorsupgradesubpubwrongversion}="Version mismatch. Please switch versions on the publisher and try again.";
$responselookup{errorsupgradesubvalid}="Valid upgrades found however the first node (publisher) must be upgraded before upgrading this node.";
$responselookup{errorsupgradetoVersionDisallowed}="Upgrade candidates found in the patch directory are not allowed by the current version";
$responselookup{errorsupgradeunexecutable}="A utility required for upgrade is not executable. Upgrade patch may be corrupted or tampered with. Please verify.";
$responselookup{errorsupgradeunknownhost}="The remote server could not be located.";
$responselookup{errorsupgradevendordirnotfound}="The Vendor directory is missing. Upgrade patch may be corrupted or tampered with. Please verify.";
$responselookup{errorsupgradeversionmismatch}="The version number inside the selected upgrade does not match the filename.";
$responselookup{errorsystem}="An error occurred but no additional information was given. Please review the Cisco Unified Communications OS Platform API logs.";
$responselookup{errorsystemparsing}="One or more system calls or files have changed resulting in a parsing error. Please review the Cisco Unified Communications OS Platform API logs.";
$responselookup{errorundeterminedresult}="The results cannot yet be located or determined.";
$responselookup{errorupgradeanotheruser}="Another user session is currently configuring an upgrade.";
$responselookup{errorupgradecancelcop}="Installation of a Cisco Options Package (COP) cannot be canceled.";
$responselookup{errorupgradecanceled}="The upgrade was canceled.";
$responselookup{errorupgradefilenotlisted}="The selected upgrade was not in the list of valid files.";
$responselookup{errorupgradefilenotready}="A valid upgrade file must be provided before an upgrade can be started.";
$responselookup{errorupgradefiltererror}="An error occured while filtering upgrade files. Please review the Cisco Unified Communications OS Platform API logs.";
$responselookup{errorupgradeinprogress}="An upgrade is already in progress.";
$responselookup{errorupgradeprogress}="An error occured while getting the upgrade progress.";
$responselookup{errorupgraderebootnotallowd}="Automatic reboots are not allowed on this hardware model.";
$responselookup{errorupgradeupgradestateerror}="An error occurred while accessing the upgrade state file. Please verify the status of the local filesystem.";
$responselookup{errorvalidationinvalid}="Validation error - required data is not valid.";
$responselookup{errorvalidationmaxlength}="Validation error - required data is too big.";
$responselookup{errorvalidationminlength}="Validation error - required data is too small.";
$responselookup{errorvalidationmustbe}="Validation error - required data must be a specific value to be valid.";
$responselookup{errorvalidationrange}="Validation error - required data is not within a certain range.";
$responselookup{errorvalidationrequired}="Validation error - required data is missing.";
$responselookup{errorversionactivenotavailable}="No active version is available.";
$responselookup{errorversioninactivenotavailable}="No inactive version is available.";
$responselookup{infoupgraderebooting}="The system upgrade was successful. A switch version request has been submitted. This can take a long time depending on the platform and database size. Please continue to monitor the switchover process from the Cisco Unified Communications OS Platform CLI. Please verify the system restarts and the correct version is active.";
$responselookup{infoupgraderebootrequired}="The system upgrade was successful. Please reboot the system to activate the change. This will also ensure services affected by the upgrade process are functioning properly.";
$responselookup{infoupgradeswitchrequired}="The system upgrade was successful. Please switch versions to activate the upgrade or reboot the system to ensure services affected by the upgrade process are functioning properly.";
$responselookup{internalerrorcmdfailed}="The indicated command could not be executed.";
$responselookup{internalerrorcmdformatting}="The indicated command could not be formatted correctly and therefore was not executed.";
$responselookup{internalerrorcmdresultsfile}="The indicated command did not generate the appropriate results file. The process results could not be determined.";
$responselookup{internalerrorcmdrunning}="The indicated command is still running.";
$responselookup{internalrequestdeniedlock}="The system is currently locked by another process. Please try again later.";
$responselookup{internalwarningcmdinterrupted}="The indicated command was interrupted before it was completed.";
$responselookup{warningupgradecanceled}="The upgrade was canceled.";
$responselookup{warningupgradeessutimestamp}="The selected upgrade file does not contain some of the security fixes currently applied to this machine. Installing the selected upgrade file will remove some previously installed security fixes.";
$responselookup{warningupgrademessagesnotdisplayed}="The upgrade file contained one or more upgrade messages that could not be displayed. Please review the Cisco Unified Communications OS Platform API logs.";
$responselookup{warningupgradenotcancelled}="An attempt to cancel the upgrade failed. Please review the Cisco Unified Communications OS Platform API logs.";
$responselookup{warningupgradenoupgrades}="The given directory was located and searched but no valid options or upgrades were available. Note, the system cannot be downgraded so option and upgrade files for previous releases were ignored.";
$responselookup{warningupgraderebootrequired}="A system reboot is required when the upgrade process completes or is canceled. This will ensure services affected by the upgrade process are functioning properly.";
$responselookup{warningupgraderemovemedia}="Please remove the DVD from the drive.";
$responselookup{warningupgradestatenotpersisted}="The upgrade state could not be saved. Other administrative sessions will not be able to assume control of this upgrade.";
$responselookup{internalrequestcomplete}="The query response was successful.";
	if ($responselookup{$nodots} eq "") {
		return $response;
	} else { 
		return $responselookup{$nodots};
	}
}

sub logtime {
	$time = localtime(time);
	($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	$newtime = sprintf ("%4d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon+1,$mday,$hour,$min,$sec);
	return $newtime;
}

sub cleanxml {
	my ($dirtyxml) = @_;
	$dirtyxml =~ s/(<\/?)[a-z0-9]+:/$1/g;
	$dirtyxml =~ s/\s\S+">/>/g;
	$dirtyxml =~ s/.*(<Body>.*<\/Body>).*/$1/;
	return $dirtyxml;
}