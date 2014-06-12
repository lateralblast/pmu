#!/usr/bin/env perl

# Name:         pmu (prtdiag Monitoring Utility)
# Version:      1.4.0
# Release:      1
# License:      CC-BA (Creative Commons By Attrbution)
#               http://creativecommons.org/licenses/by/4.0/legalcode
# Group:        System
# Source:       N/A
# URL:          http://lateralblast.com.au/
# Distribution: Solaris
# Vendor:       UNIX
# Packager:     Richard Spindler <richard@lateralblast.com.au>
# Description:  Tool for processing prtdiag and fmadm output to look for faults
#               The code is rather messy as the prtdiag output on Solaris is
#               inconsisted across versions of the OS and versions of hardware
#               For example the output for a V480 is different on Solaris 8, 9 and 10

use strict;
use Getopt::Std;
use Net::FTP;
use ExtUtils::Command;

my $version_string;
my $script_name="pmu"; my $script_file=$0; my $command_line; my $zone_name;
my $programmer_email="richard\@lateralblast.com.au"; my $syslog=0;
my $unameo; my $hostname; my $sys_release; my $kernel_name; my $machine_arch;
my $temp_dir="/var/log/$script_name"; my $solaris_arch; my $sys_arch;
my $prtdiag_output="$temp_dir/prtdiag_output"; my @prt_info; my @general_info;
my @cpu_info; my @memory_info; my @device_info; my @env_info; my @hardware_info;
my @fru_info; my @fan_info; my @temp_info; my @volume_info; my @current_info;
my @power_info; my @disk_info; my $verbose; my $do_list=0; my $do_mail=0;
my @fma_info; my $na_string="NA"; my $printr=0; my $errors=0; my %option;
my $verfle="$temp_dir/$script_name\_monversion"; my $password="guest@";
my $patch_server=""; my $username="anonymous";
my @led_info; my $date_file; my $date_string; my @change_log;
my $sys_admin="";

getopts("Vtpnhecasl:m:k:",\%option);

# Set to not use network auto updates by default
# Need to rewrite update code

$option{'n'}=1;

do_run_test();

foreach (keys %option) {
  if ($option{$_} eq 1) {
    $command_line="-$_ $command_line";
  }
  else {
    $command_line="-$_ $option{$_} $command_line";
  }
}

if (! -e "$temp_dir") {
  system("mkdir -p $temp_dir");
}

#
# do a run test and make sure a copy of the script is not already running
#

sub do_run_test {

  my $run_test;

  $run_test=`ps -ef |egrep '$script_name|prtmon' |grep -v grep |wc -l`;
  chomp($run_test);
  $run_test=~s/ //g;
  if ($run_test!~/^[1|2]$/) {
    print "$script_name is already running\n";
    exit;
  }
  return;

}

#
# Populate changelog (now defunct as version information is in script)
#

if ($option{'k'}=~/[0-9][0-9]/) {
  populate_change_log();
  print_version_change($option{'k'});
}

$date_string=`date +\%d\%m\%y`;
chomp($date_string);
$date_file="$temp_dir/$script_name$date_string";

get_sys_info();

if (!$option{'n'}) {
  check_version_stub();
}

#
# This code was used for auto updating (needs to be updated)
#

sub upgrade_script_file {

  my $remote_file="/pub/sun/$script_name/$script_name";
  my $local_file=$script_file;

  get_ftp_file($remote_file,$local_file);
  return;
}

#
# This code was used for comparing remote version to local version
# (needs updating)
#

sub check_version_stub {

  my $remote_stub; my $remori; my $local_stub=get_version_stub();
  my $remote_file="/pub/sun/$script_name/version";

  get_ftp_file($remote_file,$verfle);
  $remote_stub=`cat $verfle`;
  chomp($remote_stub);
  $remori=$remote_stub; $remote_stub=~s/\.//g;
  $remote_stub=~s/^0//g; $remote_stub=~s/\ //g;
  if ($remote_stub > $local_stub) {
    print "Local version of $script_name: $local_stub\n";
    print "Patch version of $script_name: $remote_stub\n";
    print "Upgrading $script_name to $remori ... ";
    upgrade_script_file();
    print "Done.\n";
    system("$script_file $command_line");
    exit;
  }
  return;
}

#
# This code was used for fetching the remote version (needs updating)
#

sub get_version_stub {

  my $version_stub=`grep '^# Version' $script_file |awk '{print \$3}'`;

  chomp($version_stub);
  $version_stub=~s/\.//g; $version_stub=~s/\ //g; $version_stub=~s/;//g;
  $version_stub=~s/"//g; $version_stub=~s/^0//g;
  return($version_stub);
}

#
# This code was used for fetching a file (needs updating)
#


sub get_ftp_file {

  my $remote_file=$_[0]; my $local_file=$_[1]; my $ftp_session;

  $ftp_session=Net::FTP->new("$patch_server", Passive=>1, Debug=>0);
  $ftp_session->login("$username","$password");
  $ftp_session->type("I");
  $ftp_session->get("$remote_file","$local_file");
  $ftp_session->quit;
  return;
}

#
# If given a -s send to syslog
#

if ($option{'s'}) {
  $syslog=1;
}

#
# If given a -t run in test mode and induce false errors
#

if ($option{'t'}) {
  $errors=1;
  print "Inducing false errors...\n";
}

#
# If given a -h print help
#

if ($option{'h'}) {
  print_help_info();
  exit;
}

#
# If given a -c print change log
#

if ($option{'c'}) {
  print_change_log();
  exit;
}

#
# If given a -V print version information
#

if ($option{'V'}) {
  print_version_info();
  exit;
}

#
# If given a -r set the receiver of the email
#

if ($option{'r'}) {
  $sys_admin=$option{'r'};
}

#
# Handle other switches appropriately
#

if (($option{'l'})||($option{'m'})||($option{'e'})||($option{'p'})||($option{'a'})) {
  if (($option{'l'})||($option{'a'})) {
    $do_list=1;
    $verbose=1;
  }
  if (($option{'m'})||($option{'e'})) {
    $do_mail=1;
  }
  else {
    $do_mail=0;
  }
  remove_temp_file();
  touch $prtdiag_output;
  open(PRTOUT,">$prtdiag_output");
  if ($option{'p'}) {
    $printr=1;
  }
  get_prt_info();
  process_prt_info();
  if (($option{'a'})||($option{'l'}=~/all/)||($option{'m'}=~/all/)||($option{'e'})) {
    process_all_info();
  }
  else {
    if (($option{'l'}=~/gen/)||($option{'m'}=~/gen/)) {
      process_general_info();
    }
    if (($option{'l'}=~/cpu/)||($option{'m'}=~/cpu/)) {
      process_cpu_info();
    }
    if (($option{'l'}=~/mem/)||($option{'m'}=~/mem/)) {
      process_mem_info();
    }
    if (($option{'l'}=~/iod/)||($option{'m'}=~/iod/)) {
      process_device_info();
    }
    if (($option{'l'}=~/env/)||($option{'m'}=~/env/)) {
      process_env_info(); process_fan_info(); process_temp_info();
      process_voltage_info(); process_current_info();
      process_power_info(); process_disk_info(); process_led_info();
    }
    if (($option{'l'}=~/hwr/)||($option{'m'}=~/hwr/)) {
      process_hardware_info();
    }
    if (($option{'l'}=~/fru/)||($option{'m'}=~/fru/)) {
      process_fru_info();
    }
    if (($option{'l'}=~/fan/)||($option{'m'}=~/fan/)) {
      process_env_info(); process_fan_info();
    }
    if (($option{'l'}=~/fan/)||($option{'m'}=~/led/)) {
      process_env_info(); process_led_info();
    }
    if (($option{'l'}=~/tmp/)||($option{'m'}=~/tmp/)) {
      process_env_info(); process_temp_info();
    }
    if (($option{'l'}=~/vol/)||($option{'m'}=~/vol/)) {
      process_env_info(); process_voltage_info();
    }
    if (($option{'l'}=~/cur/)||($option{'m'}=~/cur/)) {
      process_env_info(); process_current_info();
    }
    if (($option{'l'}=~/pwr/)||($option{'m'}=~/pwr/)) {
      process_env_info(); process_power_info();
    }
    if (($option{'l'}=~/dsk/)||($option{'m'}=~/dsk/)) {
      process_env_info(); process_disk_info();
    }
    if ($sys_release=~/5\.10|5\.11/) {
      if (($option{'l'}=~/fma/)||($option{'m'}=~/fma/)) {
        process_fma_info();
      }
    }
  }
  if (($option{'m'})||($option{'e'})) {
    mail_report(); remove_temp_file();
  }
  if ($do_list eq 1) {
    print "\n";
  }
  exit;
}

#
# Process fmadm information on Solaris 10 and 11
#

sub process_fma_info {

  my $counter; my $record; my $number=0; my $tester; my $name_string;
  my $status="OK"; my @fma_status; my $output; my $temp_fma; my $fmanum;

  @fma_info=`/usr/sbin/fmadm faulty |grep 'Fault class' |grep ': '`;

  for ($counter=0;$counter<@fma_info;$counter++) {
    $tester=0; $name_string=""; $status="";
    $record=$fma_info[$counter];
    chomp($record);
    if ($printr eq 1) {
      print "$record\n";
    }
    if ($record=~/^[A-z]/) {
      $tester=1;
      ($temp_fma,$name_string)=split(': ',$record);
    }
    else {
      $tester=0;
    }
    if ($tester eq 1) {
      if ($name_string=~/ok|online|GOOD/) {
        $status="OK";
      }
      else {
        if ($name_string=~/present/) {
          $status="NA";
        }
        else {
          $status="ERROR";
        }
      }
      if ($tester eq 1) {
        $fma_status[$number]="$name_string|$status"; $number++;
      }
    }
  }
  $tester=0;
  if (($do_list eq 1)||($do_mail eq 1)) {
    if ($verbose eq 1) {
      print "\n";
      print "FMA Information:\n";
    }
    for ($counter=0;$counter<@fma_status;$counter++) {
      $record=$fma_status[$counter];
      ($name_string,$status)=split('\|',$record);
      $output="$name_string $status";
      if ($verbose eq 1) {
        print "\n";
        print "\tDevice: $name_string\n";
        print "\tStatus: $status\n";
      }
      if ($do_mail eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          if ($tester eq 0) {
            print PRTOUT "\n";
            print PRTOUT "FMA Failures:\n";
            $tester=1;
          }
          $record=~s/NA\||ERROR|\|/ /g;
          print PRTOUT "WARNING: $record\n";
        }
      }
      if ($syslog eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          system("/usr/bin/logger -f $output -p kern.warning");
        }
      }
    }
  }
  return;
}

#
# Print help information
#

sub print_help_info {
  print_version_info();
  if ($sys_release=~/5\.10|5\.11/) {
    print "Usage: $script_name [-][a|e|h|v|c|n] [-l|m][cpu|mem|iod|env|fru|fan|tmp|vol|cur|pwr|dsk|all] [-r][email address] [-][t]\n";
  }
  else {
    print "Usage: $script_name [-][a|e|h|v|c|n] [-l|m][cpu|mem|iod|env|fru|fan|tmp|vol|cur|pwr|dsk|fma|all] [-r][email address] [-][t]\n";
  }
  print "\n";
  print "-l: Display System Information\n";
  print "-a: Display All System Information\n";
  print "-m: Mail Failures\n";
  print "-e: Display Failures\n";
  print "-h: Display Help\n";
  print "-v: Display Version\n";
  print "-c: Display Changelog\n";
  print "-t: Induce false errors\n";
  print "-s: Send errors to syslog\n";
  print "-n: Run without checking for updates\n";
  print "-r: Alternate recipient to one in code\n";
  print "\n";
  print "-[l|m] cpu:   Process CPU Information\n";
  print "-[l|m] mem:   Process Memory Information\n";
  print "-[l|m] iod:   Process IO Information\n";
  print "-[l|m] env:   Process Environmental Information\n";
  print "-[l|m] fru:   Process FRU Information\n";
  print "-[l|m] fan:   Process Fan Information\n";
  print "-[l|m] tmp:   Process Temperature Information\n";
  print "-[l|m] vol:   Process Voltage Information\n";
  print "-[l|m] cur:   Process Current Information\n";
  print "-[l|m] pwr:   Process Power Information\n";
  print "-[l|m] dsk:   Process Disk Information\n";
  if ($sys_release=~/5\.10|5\.11/) {
    print "-[l|m] fma:   Process FMA Information\n";
  }
  print "-[l|m] all:   Process All Information\n";
  print "\n";
  print "Examples:\n";
  print "\n";
  print "'$script_name -m all'\tProcess all information and email results\n";
  print "'$script_name -l fru'\tOnly display FRU information\n";
  print "\n";

  return;
}

sub process_all_info {

  process_general_info();
  process_cpu_info();
  process_mem_info();
  process_device_info();
  process_hardware_info();
  process_fru_info();
  process_env_info();
  process_fan_info();
  process_temp_info();
  process_voltage_info();
  process_current_info();
  process_power_info();
  process_disk_info();
  process_led_info();
  if ($sys_release=~/5\.10|5\.11/) {
    process_fma_info();
  }
  return;

}

#
# Print change in version information
#

sub print_version_change {

  my $number=$_[0]; my $counter; my $record;

  print "\n";
  if ($number!~/[0-9]/) {
    print "Fixes since last update:\n";
  }
  else {
    print "Fixes since $number:\n";
  }
  print "\n";
  $number=~s/\.//g;
  for ($counter=$number; $counter<@change_log; $counter++) {
    $record=$change_log[$counter];
    chomp($record);
    print "$record\n";
  }
  return;
}

#
# Print changelog (needs updating)
#

sub print_change_log {

  my $counter; my $record; my $temp_version; my $temp_name; my $tmpdat; my $tmpstr;

  if ($change_log[0]!~/[A-z]/) {
    populate_change_log();
  }
  print_version_info();
  for ($counter=0; $counter<@change_log; $counter++) {
    $record=$change_log[$counter];
    chomp($record);
    print "$record\n";
  }
  print "\n";
  return;
}

#
# Populate change log (needs updating)
#

sub populate_change_log {

  my $remote_file="/pub/sun/$script_name/changelog"; my $counter;
  my $local_file="/tmp/changelog"; my $record;

  if (-e "$local_file") {
    system("rm $local_file");
  }
  get_ftp_file($remote_file,$local_file);
  if (-e "$local_file") {
    @change_log=`cat $local_file`;
  }
  return;
}

#
# Print version information
#

sub print_version_info {
  print "\n";
  $version_string=`grep '^# Version' $script_file |awk '{print \$3}'`;
  print "$script_name v. $version_string\n";
  print "$programmer_email\n";
  print "\n";
  return;
}

#
# Get System Information
#

sub get_sys_info {

  my $prefix; my $counter; my $record;
  my @date_list=`ls $temp_dir |grep mdlog |grep -v '$date_string'`;

  if (!-e "$temp_dir") {
    system("mkdir -p $temp_dir");
  }
  for ($counter=0; $counter<@date_list; $counter++) {
    $record=$date_list[$counter];
    chomp($record);
    system("cd $temp_dir ; rm $record");
  }
  $unameo=`uname -a`;
  chomp($unameo);
  ($prefix,$hostname,$sys_release,$kernel_name,$machine_arch,$solaris_arch,$sys_arch)=split(' ',$unameo);
  if ($sys_release=~/5\.10|5\.11/) {
    $zone_name=`/usr/bin/zonename`;
    chomp($zone_name);
    if ($zone_name!~/global/) {
      print "Script must be run on a global zone\n";
      exit;
    }
  }
  return;
}

#
# Get prtdiag output
#

sub get_prt_info {

  my $record; my $counter; my $prt_command;

  if ($sys_arch=~/i386|i86pc/) {
    $prt_command="/usr/sbin/prtdiag";
  }
  else {
    $prt_command="/usr/platform/$sys_arch/sbin/prtdiag";
  }
  @prt_info=`$prt_command -vv`;
  if ($errors eq 1) {
    for ($counter=0;$counter<@prt_info;$counter++) {
      $record=$prt_info[$counter];
      if ($record=~/okay|ok|OK|NO_FAULT|online|present|GOOD|NA/) {
        $record=~s/okay/ERROR/g; $record=~s/ok/ERROR/g;
        $record=~s/ OK/ ERROR/g; $record=~s/NO_FAULT/ERROR/g;
        $record=~s/online/ERROR/g; $record=~s/present/ERROR/g;
        $record=~s/NA/ERROR/g;
        $prt_info[$counter]=$record;
      }
    }
  }
  return;
}

#
# Process prtdiag information and split it up into separate arrays
#

sub  process_prt_info {

  my $record; my $status="OK"; my $counter; my $number=0;
  my $general_count=0; my $cpu_count=0; my $mem_count=0; my $iod_count=0;
  my $env_count=0; my $hardware_count=0; my $fru_count=0; my $tester=0;

  for ($counter=0;$counter<@prt_info;$counter++) {
    $record=$prt_info[$counter];
    chomp($record);
    $record=~s/faulty/FAULTY/g; $record=~s/failed/FAULTY/g;
    if ($record=~/= CPUs|= Processor Sockets/) {
      $number=1;
    }
    if ($record=~/= Memory/) {
      $number=2;
    }
    if ($record=~/= IO Cards|= IO Devices |= IO Configuration|= On-board |= Upgradeable Slots/) {
      $number=3;
    }
    if ($record=~/Environmental Status/) {
      $number=4;
    }
    if ($record=~/= HW Revisions/) {
      $number=5;
    }
    if ($record=~/= FRU /) {
      $number=6;
    }
    if (($record!~/^=/)&&($record!~/^$/)) {
      if ($number eq 0) {
        $general_info[$general_count]=$record; $general_count++;
      }
      if ($number eq 1) {
        $cpu_info[$cpu_count]=$record; $cpu_count++;
      }
      if ($number eq 2) {
        $memory_info[$mem_count]=$record; $mem_count++;
      }
      if ($number eq 3) {
        $device_info[$iod_count]=$record; $iod_count++;
      }
      if ($number eq 4) {
        $env_info[$env_count]=$record; $env_count++;
      }
      if ($number eq 5) {
        $hardware_info[$hardware_count]=$record; $hardware_count++;
      }
      if ($number eq 6) {
        $fru_info[$fru_count]=$record; $fru_count++;
      }
    }
  }
  for ($counter=0;$counter<@hardware_info;$counter++) {
    $record=$hardware_info[$counter];
    chomp($record);
    if ($record=~/OBP|CORE/) {
      $tester=1;
    }
  }
  if ($tester eq 0) {
    $counter++;
    $hardware_info[$counter]=`/usr/sbin/prtconf -V`;
  }
  return;
}

#
# Print general information from prtdiag
#

sub print_general_info {
  print "\n";
  print " @general_info\n";
  print "\n";
  return;
}

#
# Process general information from prtdiag
#

sub process_general_info {

  my $counter; my $record;

  if ($verbose eq 1) {
    print "System Information:\n";
    print "\n";
  }
  for ($counter=0;$counter<@general_info;$counter++) {
    $record=$general_info[$counter];
    chomp($record);
    if ($verbose eq 1) {
      print "\t$record\n";
    }
    if ($printr eq 1) {
      print "$record\n";
    }
  }
  return;
}

sub print_cpu_info {
  print "\n";
  print "========================= CPUs ===============================================\n";
  print "\n";
  print " @cpu_info\n";
  print "\n";
  return;
}

sub print_memory_info {
  print "\n";
  print "========================= Memory Configuration ===============================\n";
  print "\n";
  print " @memory_info\n";
  print "\n";
  return;
}

sub print_device_info {
  print "\n";
  print "========================= IO Cards =========================\n";
  print "\n";
  print " @device_info\n";
  print "\n";
  return;
}

sub print_env_info {
  print "\n";
  print "=========================  Environmental Status =========================\n";
  print "\n";
  print " @env_info\n";
  print "\n";
  return;
}

sub print_hardware_info {
  print "\n";
  print "========================= HW Revisions =======================================\n";
  print "\n";
  print " @hardware_info\n";
  print "\n";
  return;
}

sub print_fru_info {
  print "\n";
  print "=========================== FRU Operational Status ===========================\n";
  print "\n";
  print " @fru_info\n";
  print "\n";
  return;
}

#
# Process CPU information from prtdiag
#

sub process_cpu_info {

  my $counter; my $record; my $tester; my $cpu_no; my $cpu_freq;
  my $prefix; my $cpu_cache; my $name_string; my $cpu_mask; my $cpu_die;
  my $fan_unit; my $cpu_board; my @cpu_status; my $number=0; my $cpuimp;
  my $cpu_ambient; my $status="OK"; my $cpu_location; my $fan_speed;
  my $cpu_model; my $output; my $core_1; my $core_2;

  for ($counter=0;$counter<@cpu_info;$counter++) {
    $name_string=""; $cpu_board=""; $cpu_no=""; $cpu_cache="";
    $cpu_freq=""; $cpu_mask=""; $cpu_die=""; $cpu_ambient="";
    $cpu_location=""; $fan_speed=""; $fan_unit=""; $status="";
    $record=$cpu_info[$counter];
    chomp($record);
    if ($printr eq 1) {
      print "$record\n";
    }
    $tester=0;
    if (($record=~/II|0|AMD/)) {
      $tester=1;
      if ($sys_arch=~/i386|i86pc/) {
        $name_string=$record;
      }
      if ($sys_arch=~/440|240|210/) {
        if ($sys_release=~/9|10/) {
          ($cpu_no,$cpu_freq,$prefix,$cpu_cache,$name_string,$cpu_mask,$cpu_die,$cpu_ambient,$status,$cpu_location)=split(' ',$record);
        }
        else {
          ($cpu_no,$cpu_freq,$prefix,$cpu_cache,$name_string,$cpu_mask,$cpu_die,$cpu_ambient,$fan_speed,$fan_unit)=split(' ',$record);
        }
        if ($cpu_die=~/\-/) {
          $cpu_die=$na_string;
        }
        if ($cpu_ambient=~/\-/) {
          $cpu_ambient=$na_string;
        }
      }
      if (($sys_arch=~/Ultra-Enterprise|Ultra-60/)&&($sys_arch!~/10000/)) {
        ($cpu_board,$cpu_no,$cpu_model,$cpu_freq,$cpu_cache,$name_string,$cpu_mask)=split(' ',$record);
      }
      if ($sys_arch=~/480|880|280/) {
        ($cpu_board,$cpu_no,$cpu_freq,$cpu_cache,$name_string,$cpu_mask)=split(' ',$record);
      }
      if ($sys_arch=~/490|890/) {
        ($cpu_board,$core_1,$core_2,$cpu_freq,$cpu_cache,$name_string,$cpu_mask)=split(' ',$record);
        $cpu_no="$core_1 $core_2";
      }
      if ($sys_arch=~/Ultra-5_10|UltraAX-i2|Ultra-Enterprise-10000/) {
        ($prefix,$prefix,$prefix,$cpu_freq,$cpu_cache,$cpuimp,$cpu_mask)=split(' ',$record);
        if ($cpuimp=~/12/) {
          $name_string="UltraSPARC-IIi";
        }
        if ($cpuimp=~/13/) {
          $name_string="UltraSPARC-IIe";
        }
      }
      if ($sys_arch=~/Ultra-4|Ultra-250/) {
        ($cpu_board,$cpu_no,$prefix,$cpu_freq,$cpu_cache,$name_string,$cpu_mask)=split(' ',$record);
      }
      if ($sys_arch=~/Sun-Fire-T1000|Sun-Fire-T200|T5120|T5220|T6300|T6220|T6320/) {
        if ($record=~/CMP/) {
          ($cpu_board,$cpu_no,$cpu_freq,$prefix,$name_string)=split(' ',$record);
        }
      }
      if ($sys_arch=~/Sun-Blade-100/) {
        if ($sys_release=~/8/) {
          ($cpu_no,$cpu_freq,$prefix,$cpu_cache,$name_string,$cpu_mask,$cpu_die,$prefix,$cpu_ambient,$prefix)=split(' ',$record);
        }
        else {
          ($cpu_no,$cpu_freq,$prefix,$cpu_cache,$name_string,$cpu_mask,$cpu_die,$cpu_ambient,$cpu_location)=split(' ',$record);
        }
      }
    }
    if (($name_string!~/[A-z]/)&&($name_string!~/[0-9]/)) {
      $name_string=$na_string;
    }
    if (($cpu_board!~/[A-z]/)&&($cpu_board!~/[0-9]/)) {
      $cpu_board=$na_string;
    }
    if (($cpu_no!~/[A-z]/)&&($cpu_no!~/[0-9]/)) {
      $cpu_no=$na_string;
    }
    if (($cpu_cache!~/[A-z]/)&&($cpu_cache!~/[0-9]/)) {
      $cpu_cache=$na_string;
    }
    if (($cpu_freq!~/[A-z]/)&&($cpu_freq!~/[0-9]/)) {
      $cpu_freq=$na_string;
    }
    if (($cpu_mask!~/[A-z]/)&&($cpu_mask!~/[0-9]/)) {
      $cpu_mask=$na_string;
    }
    if (($cpu_die!~/[A-z]/)&&($cpu_die!~/[0-9]/)) {
      $cpu_die=$na_string;
    }
    if (($cpu_ambient!~/[A-z]/)&&($cpu_ambient!~/[0-9]/)) {
      $cpu_ambient=$na_string;
    }
    if (($cpu_location!~/[A-z]/)&&($cpu_location!~/[0-9]/)) {
      $cpu_location=$na_string;
    }
    if (($fan_speed!~/[A-z]/)&&($fan_speed!~/[0-9]/)) {
      $fan_speed=$na_string;
    }
    if (($fan_unit!~/[A-z]/)&&($fan_unit!~/[0-9]/)) {
      $fan_unit=$na_string;
    }
    if (($status!~/[A-z]/)&&($status!~/[0-9]/)) {
      $status=$na_string;
    }
    if ($status=~/online|ok/) {
      $status="OK";
    }
    if ($tester eq 1) {
      $cpu_status[$number]="$name_string|$cpu_board|$cpu_no|$cpu_cache|$cpu_freq|$cpu_mask|$cpu_die|$cpu_ambient|$cpu_location|$fan_speed|$fan_unit|$status";
      $number++;
    }
  }
  $tester=0;
  if (($do_list eq 1)||($do_mail eq 1)) {
    if ($verbose eq 1) {
      print "\n";
      print "CPU Information:\n";
    }
    for ($counter=0;$counter<@cpu_status;$counter++) {
      $record=$cpu_status[$counter];
      ($name_string,$cpu_board,$cpu_no,$cpu_cache,$cpu_freq,$cpu_mask,$cpu_die,$cpu_ambient,$cpu_location,$fan_speed,$fan_unit,$status)=split('\|',$record);
      $output="$name_string $cpu_board $cpu_no $cpu_cache $cpu_freq $cpu_mask $cpu_die $cpu_ambient $cpu_location $fan_speed $fan_unit $status";
      if ($verbose eq 1) {
        print "\n";
        print "\tDevice:   $name_string\n";
        print "\tBoard:    $cpu_board\n";
        print "\tNumber:   $cpu_no\n";
        print "\tCache:    $cpu_cache\n";
        print "\tFreq:     $cpu_freq\n";
        print "\tMask:     $cpu_mask\n";
        print "\tLocation: $cpu_location\n";
        print "\tDie:      $cpu_die\n";
        print "\tAmbient:  $cpu_ambient\n";
        print "\tFan:      $fan_speed\n";
        print "\tUnit:     $fan_unit\n";
        print "\tStatus:   $status\n";
      }
      if ($do_mail eq 1) {
        if ($status!~/OK|$na_string/) {
          if ($tester eq 0) {
            print PRTOUT "\n";
            print PRTOUT "CPU Failures:\n";
            $tester=1;
          }
          $record=~s/NA\||ERROR|\|/ /g;
          print PRTOUT "WARNING: $record\n";
        }
      }
      if ($syslog eq 1) {
        if ($status!~/OK|$na_string/) {
          system("/usr/bin/logger -f $output -p kern.warning");
        }
      }
    }
  }
  return;
}

#
# Process memory information from prtdiag
#

sub process_mem_info {

  my $counter; my $record; my $mem_base=$na_string; my $mem_size=$na_string;
  my $mem_int=$na_string; my $mem_loc=$na_string; my $board_no=$na_string;
  my $mem_mcid=$na_string; my $mem_log=$na_string; my $status=$na_string;
  my $mem_dimm=$na_string; my $intwth=$na_string; my $mem_bank=$na_string;
  my $cpulat=$na_string; my $number=0; my @mem_status; my $tester=0;
  my $prefix; my $bank_one; my $bnktwo; my $bnkthr; my $bnkfor;
  my $output;

  for ($counter=0;$counter<@memory_info;$counter++) {
    $mem_size=""; $mem_base=""; $mem_dimm=""; $board_no="";
    $mem_bank=""; $mem_mcid=""; $mem_log=""; $mem_int="";
    $mem_loc=""; $bank_one=""; $bnktwo=""; $bnkthr="";
    $bnkfor=""; $record=$memory_info[$counter];
    chomp($record);
    if ($printr eq 1) {
      print "$record\n";
    }
    $tester=0;
    if (($record=~/DIMM|BankIDs|way|none|Board/)&&($record!~/Interleave/)) {
      $tester=1;
      if ($sys_arch=~/i386|i86pc/) {
        ($prefix,$mem_loc)=split("DIMM",$record);
        ($mem_loc,$prefix)=split(" ",$mem_loc);
        ($prefix,$mem_bank)=split("BANK",$record);
        ($mem_dimm,$prefix)=split(" ",$record);
      }
      if ($sys_arch=~/Sun-Blade-100/) {
        ($mem_base,$mem_size,$mem_int,$mem_loc)=split(' ',$record);
      }
      if ($sys_arch=~/440|240|210/) {
        ($mem_base,$mem_size,$mem_int,$prefix,$mem_loc)=split(' ',$record);
      }
      if ($sys_arch=~/480|490|880|280|890/) {
        ($board_no,$mem_mcid,$mem_log,$mem_size,$status,$mem_dimm,$mem_int,$intwth)=split(' ',$record);
      }
      if ($sys_arch=~/Ultra-4|Ultra-250/) {
        ($mem_bank,$mem_int,$mem_loc,$mem_size,$status)=split(' ',$record);
        $mem_size="$mem_size MB";
      }
      if (($sys_arch=~/Ultra-Enterprise/)&&($sys_arch!~/10000/)) {
        ($board_no,$mem_bank,$mem_size,$prefix,$status,$cpulat,$mem_int,$intwth)=split(' ',$record);
      }
      if ($sys_arch=~/Ultra-Enterprise-10000/) {
        ($prefix,$board_no,$bank_one,$bnktwo,$bnkthr,$bnkfor)=split(' ',$record);
        $mem_size="$bank_one $bnktwo $bnkthr $bnkfor";
      }
    }
    if (($board_no!~/[A-z]/)&&($board_no!~/[0-9]/)) {
      $board_no=$na_string;
    }
    if (($mem_bank!~/[A-z]/)&&($mem_bank!~/[0-9]/)) {
      $mem_bank=$na_string;
    }
    if (($mem_mcid!~/[A-z]/)&&($mem_mcid!~/[0-9]/)) {
      $mem_mcid=$na_string;
    }
    if (($mem_log!~/[A-z]/)&&($mem_log!~/[0-9]/)) {
      $mem_log=$na_string;
    }
    if (($status!~/[A-z]/)&&($status!~/[0-9]/)) {
      $status=$na_string;
    }
    if (($mem_dimm!~/[A-z]/)&&($mem_dimm!~/[0-9]/)) {
      $mem_dimm=$mem_size;
    }
    if (($intwth!~/[A-z]/)&&($intwth!~/[0-9]/)) {
      $intwth=$na_string;
    }
    if (($mem_size!~/[A-z]/)&&($mem_size!~/[0-9]/)) {
      $mem_size=$na_string;
    }
    if (($mem_base!~/[A-z]/)&&($mem_base!~/[0-9]/)) {
      $mem_base=$na_string;
    }
    if (($mem_int!~/[A-z]/)&&($mem_int!~/[0-9]/)) {
      $mem_int=$na_string;
    }
    if (($mem_loc!~/[A-z]/)&&($mem_loc!~/[0-9]/)) {
      $mem_loc=$na_string;
    }
    if ($status=~/no_status/) {
      $status=$na_string;
    }
    if (($status=~/ok|online|GOOD/)||($record=~/in use/)) {
      $status="OK";
    }
    if ($tester eq 1) {
      $mem_status[$number]="$mem_size|$mem_base|$mem_dimm|$board_no|$mem_bank|$mem_mcid|$mem_log|$mem_int|$mem_loc";
      $number++;
    }
  }
  if ($sys_arch=~/UltraAX-i2|Ultra-60/) {
    ($prefix,$prefix,$mem_size,$prefix)=split(' ',$general_info[2]);
    $mem_size="$mem_size MB";
    $mem_status[0]="$mem_size|$mem_base|$mem_dimm|$board_no|$mem_bank|$mem_mcid|$mem_log|$mem_int|$mem_loc";
  }
  $tester=0;
  if (($do_list eq 1)||($do_mail eq 1)) {
    if ($verbose eq 1) {
      print "\n";
      print "Memory Information:\n";
    }
    for ($counter=0;$counter<@mem_status;$counter++) {
      $record=$mem_status[$counter];
      ($mem_size,$mem_base,$mem_dimm,$board_no,$mem_bank,$mem_mcid,$mem_log,$mem_int,$mem_loc)=split('\|',$record);
      $output="$mem_size $mem_base $mem_dimm $board_no $mem_bank $mem_mcid $mem_log $mem_int $mem_loc";
      if ($verbose eq 1) {
        print "\n";
        print "\tSize:       $mem_size\n";
        print "\tAddress:    $mem_base\n";
        print "\tDIMM:       $mem_dimm\n";
        print "\tBoard:      $board_no\n";
        print "\tBank:       $mem_bank\n";
        print "\tMCID:       $mem_mcid\n";
        print "\tLogical:    $mem_log\n";
        print "\tInterleave: $mem_int\n";
        print "\tLocation:   $mem_loc\n";
        print "\tStatus:     $status\n";
      }
      if ($do_mail eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          if ($tester eq 0) {
            print PRTOUT "\n";
            print PRTOUT "Memory Failures:\n";
            $tester=1;
          }
          $record=~s/NA\||ERROR|\|/ /g;
          print PRTOUT "WARNING: $record\n";
        }
      }
      if ($syslog eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          system("/usr/bin/logger -f $output -p kern.warning");
        }
      }
    }
  }
  return;
}

#
# Process device information form prtdiag
#

sub process_device_info {

  my $counter; my $record; my $prefix; my $suffix; my $io_type;
  my $port_id; my $bus_side; my $slot_no; my $bus_freq; my $devfun;
  my $status="OK"; my $name_string; my $model_info; my $board_no; my $bus_type;
  my $port_id; my $dev_funct; my $io_path; my @iodsta; my $number=0;
  my $tester=0; my $checkr=0; my $tmprec; my $output; my @line;

  for ($counter=0;$counter<@device_info;$counter++) {
    $tester=0; $name_string=""; $io_type=""; $model_info="";
    $bus_type=""; $slot_no=""; $port_id=""; $dev_funct="";
    $bus_side=""; $board_no=""; $io_path=""; $bus_freq="";
    $status=""; $record=$device_info[$counter];
    chomp($record);
    if ($printr eq 1) {
      print "$record\n";
    }
    if ($record=~/PCI|pci|SBus/) {
      $tester=1;
      if ($sys_arch=~/i386|i86/) {
        if ($record=~/PCIE/) {
          $name_string="PCIe";
          $io_type="PCIe";
        }
        else {
          $name_string="PCI";
          $io_type="PCI";
        }
        @line=split(/\s+/,$record);
        $port_id=$line[0];
        $slot_no=$line[-1];
        if ($slot_no=~/-/) {
          ($bus_type,$slot_no)=split("-",$slot_no);
        }
      }
      if ($sys_arch=~/UltraAX-i2|Ultra-Enterprise|Ultra-Enterprise-10000|Ultra-60/) {
        if ($record!~/\(/) {
          ($board_no,$bus_type,$bus_freq,$slot_no,$name_string,$model_info)=split(' ',$record);
        }
        else {
          ($board_no,$bus_type,$bus_freq,$slot_no,$name_string,$io_type,$model_info)=split(' ',$record);
        }
      }
      if ($sys_arch=~/Sun-Fire-T1000|Sun-Fire-T200|T5120|T5220|T6300|T6220|T6320/) {
        if ($record=~/^MB/) {
          ($board_no,$bus_type,$slot_no,$io_path,$name_string)=split(' ',$record);
          if (($io_type=~/network/)&&($board_no=~/NET/)) {
            ($prefix,$name_string)=split('/',$board_no);
          }
        }
      }
      if ($sys_arch=~/440|240|210/) {
        if ($sys_release=~/8/) {
          ($board_no,$bus_type,$bus_freq,$slot_no,$name_string,$io_type,$model_info)=split(' ',$record);
        }
        if ($sys_release=~/9|10/) {
          if ($record=~/^pci/) {
            $checkr=$counter;
            ($bus_type,$bus_freq,$slot_no,$name_string,$io_type,$model_info)=split(' ',$record);
            $checkr++;
            $tmprec=$device_info[$checkr];
            ($status,$io_path)=split(' ',$tmprec);

          }
        }
      }
      if ($sys_arch=~/480|490/) {
        $bus_type="pci";
        if ($record=~/^PCI/) {
          if ($record=~/\(/) {
            ($board_no,$port_id,$bus_side,$slot_no,$bus_freq,$suffix,$dev_funct,$status,$name_string,$io_type,$model_info)=split(' ',$record);
          }
          else {
            ($board_no,$port_id,$bus_side,$slot_no,$bus_freq,$suffix,$dev_funct,$status,$name_string,$model_info)=split(' ',$record);
          }
        }
        if ($io_type!~/[A-z]/) {
          if ($name_string=~/scs/) {
            $io_type="scsi";
          }
        }
      }
      if ($sys_arch=~/880|280|890/) {
        if ($record=~/device on pci-bridge/) {
          $model_info="device on pci-bridge";
        }
        if ($record=~/^I\/O/) {
          if ($record=~/\(/) {
            ($prefix,$board_no,$port_id,$bus_side,$slot_no,$bus_freq,$suffix,$dev_funct,$status,$name_string,$io_type,$model_info)=split(' ',$record);
          }
          else {
            ($prefix,$board_no,$port_id,$bus_side,$slot_no,$bus_freq,$suffix,$dev_funct,$status,$name_string,$model_info)=split(' ',$record);
          }
        }
        if ($io_type!~/[A-z]/) {
          if ($name_string=~/scs/) {
            $io_type="scsi";
          }
        }

      }
      if ($sys_arch=~/Ultra-4|Ultra-250/) {
        ($board_no,$bus_type,$bus_freq,$slot_no,$name_string,$model_info)=split(' ',$record);
      }
      if ($sys_arch=~/Sun-Blade-100/) {
        ($board_no,$bus_type,$bus_freq,$slot_no,$name_string,$io_type,$model_info)=split(' ',$record);
      }
      if ($io_type=~/\+/) {
        if ($io_type=~/ser/) {
          $io_type="serial";
        }
        if ($io_type=~/scs/) {
          $io_type="scsi";
        }
      }
      else {
        $io_type=~s/\(//g; $io_type=~s/\)//g;
      }
      if (($name_string!~/[A-z]/)&&($name_string!~/[0-9]/)) {
        $name_string=$na_string;
      }
      if (($io_type!~/[A-z]/)&&($io_type!~/[0-9]/)) {
        $io_type=$na_string;
      }
      if (($model_info!~/[A-z]/)&&($model_info!~/[0-9]/)) {
        $model_info=$na_string;
      }
      if (($bus_type!~/[A-z]/)&&($bus_type!~/[0-9]/)) {
        $bus_type=$na_string;
      }
      if (($slot_no!~/[A-z]/)&&($slot_no!~/[0-9]/)) {
        $slot_no=$na_string;
      }
      if (($port_id!~/[A-z]/)&&($port_id!~/[0-9]/)) {
        $port_id=$na_string;
      }
      if (($dev_funct!~/[A-z]/)&&($dev_funct!~/[0-9]/)) {
        $dev_funct=$na_string;
      }
      if (($bus_side!~/[A-z]/)&&($bus_side!~/[0-9]/)) {
        $bus_side=$na_string;
      }
      if (($board_no!~/[A-z]/)&&($board_no!~/[0-9]/)) {
        $board_no=$na_string;
      }
      if (($io_path!~/[A-z]/)&&($io_path!~/[0-9]/)) {
        $io_path=$na_string;
      }
      if (($bus_freq!~/[A-z]/)&&($bus_freq!~/[0-9]/)) {
        $bus_freq=$na_string;
      }
      if (($status!~/[A-z]/)&&($status!~/[0-9]/)) {
        $status=$na_string;
      }
      if (($status=~/ok|online|GOOD/)||($record=~/in use/)) {
        $status="OK";
      }
      if ($tester eq 1) {
        if ($name_string!~/NA/) {
          $iodsta[$number]="$name_string|$io_type|$model_info|$bus_type|$slot_no|$port_id|$dev_funct|$bus_side|$board_no|$io_path|$bus_freq|$status";
          $number++;
        }
      }
    }
  }
  $tester=0;
  if (($do_list eq 1)||($do_mail eq 1)) {
    if ($verbose eq 1) {
      print "\n";
      print "IO Information:\n";
    }
    for ($counter=0;$counter<@iodsta;$counter++) {
      $record=$iodsta[$counter];
      ($name_string,$io_type,$model_info,$bus_type,$slot_no,$port_id,$dev_funct,$bus_side,$board_no,$io_path,$bus_freq,$status)=split('\|',$record);
      $output="$name_string $io_type $model_info $bus_type $slot_no $port_id $dev_funct $bus_side $board_no $io_path $bus_freq $status";
      if ($verbose eq 1) {
        print "\n";
        print "\tDevice: $name_string\n";
        print "\tType:   $io_type\n";
        print "\tModel:  $model_info\n";
        print "\tBus:    $bus_type\n";
        print "\tSlot:   $slot_no\n";
        print "\tPort:   $port_id\n";
        print "\tFunc:   $dev_funct\n";
        print "\tSide:   $bus_side\n";
        print "\tBoard:  $board_no\n";
        print "\tPath:   $io_path\n";
        print "\tFreq:   $bus_freq\n";
        print "\tStatus: $status\n";
      }
      if ($do_mail eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          if ($tester eq 0) {
            print PRTOUT "\n";
            print PRTOUT "IO Failures:\n";
            $tester=1;
          }
          $record=~s/NA\||ERROR|\|/ /g;
          print PRTOUT "WARNING: $record\n";
        }
      }
      if ($syslog eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          system("/usr/bin/logger -f $output -p kern.warning");
        }
      }
    }
  }
  return;
}

#
# Process environmental information from prtdiag
#

sub process_env_info {

  my $counter; my $record; my $prefix; my $field_type;
  my $fan_count=0; my $tmp_count=0; my $voltage_count=0; my $current_count=0;
  my $power_count=0; my $disk_count=0; my $led_count=0;

  for ($counter=0;$counter<@env_info;$counter++) {
    $record=$env_info[$counter];
    chomp($record);
    if ($record=~/^Fan Speeds|^Fans|^Fan Bank|^Fan Status/) {
      $field_type=1;
    }
    if ($record=~/^Temperature sensors|^System Temperatures/) {
      $field_type=2;
    }
    if ($record=~/^Voltage sensors/) {
      $field_type=3;
    }
    if ($record=~/^Current sensors/) {
      $field_type=4;
    }
    if ($record=~/^Power Supplies/) {
      $field_type=5;
    }
    if ($record=~/^Disk LED Status|^Disk Status/) {
      $field_type=6;
    }
    if ($record=~/^Led State/) {
      $field_type=7;
    }
    if ($field_type eq 1) {
      $fan_info[$fan_count]=$record; $fan_count++
    }
    if ($field_type eq 2) {
      $temp_info[$tmp_count]=$record; $tmp_count++
    }
    if ($field_type eq 3) {
      $volume_info[$voltage_count]=$record; $voltage_count++
    }
    if ($field_type eq 4) {
      $current_info[$current_count]=$record; $current_count++
    }
    if ($field_type eq 5) {
      $power_info[$power_count]=$record; $power_count++
    }
    if ($field_type eq 6) {
      $disk_info[$disk_count]=$record; $disk_count++
    }
    if ($field_type eq 7) {
      $led_info[$led_count]=$record; $led_count++
    }
  }
  return;
}

#
# Process FRU information from prtdiag
#

sub process_fru_info {

  my $counter; my $record; my $number=0; my $tester; my $name_string;
  my $status="OK"; my @fru_status; my $output; my $temp_fru; my $frunum;

  for ($counter=0;$counter<@fru_info;$counter++) {
    $tester=0; $name_string=""; $status="";
    $record=$fru_info[$counter];
    chomp($record);
    if ($printr eq 1) {
      print "$record\n";
    }
    if ($sys_arch=~/440|240|210/) {
      if ($record=~/^SC|^PS|^HDD|^MB/) {
        $tester=1;
        ($name_string,$status)=split(' ',$record);
      }
      else {
        $tester=0;
      }
    }
    if ($tester eq 1) {
      if (($name_string!~/[A-z]/)&&($name_string!~/[0-9]/)) {
        $name_string=$na_string;
      }
      if (($status!~/[A-z]/)&&($status!~/[0-9]/)) {
        $status=$na_string;
      }
      if ($status=~/ok|online|GOOD/) {
        $status="OK";
      }
      if ($status=~/present/) {
        $status="NA";
      }
      for ($frunum=0;$frunum<@fru_status;$frunum++) {
        $temp_fru=$fru_status[$frunum];
        if ($temp_fru=~/$name_string/) {
          $tester=0;
        }
      }
      if ($tester eq 1) {
        $fru_status[$number]="$name_string|$status"; $number++;
      }
    }
  }
  $tester=0;
  if (($do_list eq 1)||($do_mail eq 1)) {
    if ($verbose eq 1) {
      print "\n";
      print "FRU Information:\n";
    }
    for ($counter=0;$counter<@fru_status;$counter++) {
      $record=$fru_status[$counter];
      ($name_string,$status)=split('\|',$record);
      $output="$name_string $status";
      if ($verbose eq 1) {
        print "\n";
        print "\tDevice: $name_string\n";
        print "\tStatus: $status\n";
      }
      if ($do_mail eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          if ($tester eq 0) {
            print PRTOUT "\n";
            print PRTOUT "FRU Failures:\n";
            $tester=1;
          }
          $record=~s/NA\||ERROR|\|/ /g;
          print PRTOUT "WARNING: $record\n";
        }
      }
      if ($syslog eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          system("/usr/bin/logger -f $output -p kern.warning");
        }
      }
    }
  }
  return;
}

#
# Process LED information form prtdiag
#

sub process_led_info {

  my $record; my $counter; my $status="OK"; my @led_status;
  my $name_string; my $led_name; my @led_status; my $led_col;
  my $led_no=0; my $output; my $tester;

  for ($counter=0; $counter<@led_info; $counter++) {
    $record=$led_info[$counter];
    chomp($record);
    if ($record=~/^MB|^HDD|^PSU/) {
      if ($record=~/SERVICE/) {
        ($name_string,$led_name,$status,$led_col)=split(' ',$record);
        if ($status=~/off|GOOD/) {
          $status="OK";
        }
        else {
          $status="ERROR";
        }
        $led_status[$led_no]="$name_string|$status"; $led_no++;
      }
    }
  }
  if (($do_list eq 1)||($do_mail eq 1)) {
    if ($verbose eq 1) {
      print "\n";
      print "LED Information:\n";
    }
    for ($counter=0;$counter<@led_status;$counter++) {
      $record=$led_status[$counter];
      ($name_string,$status)=split('\|',$record);
      $output="$name_string $status";
      if ($verbose eq 1) {
        print "\n";
        print "\tDevice: $name_string\n";
        print "\tStatus: $status\n";
      }
      if ($do_mail eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          if ($tester eq 0) {
            print PRTOUT "\n";
            print PRTOUT "FRU Failures:\n";
            $tester=1;
          }
          $record=~s/NA\||ERROR|\|/ /g;
          print PRTOUT "WARNING: $record\n";
        }
      }
      if ($syslog eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          system("/usr/bin/logger -f $output -p kern.warning");
        }
      }
    }
  }
  return;
}

#
# Process hardware information from prtdiag
#

sub process_hardware_info {

  my $counter; my $record; my $io_path; my $name_string; my $status="OK";
  my $device_rev; my $prefix; my $io_type; my @hardware_status; my $number=0;
  my $tester; my $port_id; my $board_no; my $sbus_one; my $sbus_two;
  my $fhc_name; my $ac_voltage; my $feps_no; my $capspd; my $fhc_no;
  my $output;

  for ($counter=0;$counter<@hardware_info;$counter++) {
    $name_string=""; $board_no=""; $fhc_no=""; $feps_no="";
    $io_type=""; $io_path=""; $port_id=""; $device_rev="";
    $status=""; $record=$hardware_info[$counter];
    chomp($record);
    if ($printr eq 1) {
      print "$record\n";
    }
    $tester=0;
    if ($sys_arch=~/440|240|210/) {
      if ($record=~/pci/) {
        $tester=1;
        $port_id=$na_string;
        if ($sys_release=~/9|10/) {
          $io_type="pci";
          ($io_path,$name_string,$status,$device_rev)=split(' ',$record);
        }
        else {
          $io_type="pci";
          ($prefix,$prefix,$device_rev)=split(' ',$record);
        }
      }
    }
    if ($sys_arch=~/Sun-Fire-T1000|Sun-Fire-T200|T5120|T5220|T6300|T6220|T6320/) {
      if ($record=~/IOBD/) {
        $tester=1;
        ($board_no,$io_path,$io_type,$device_rev)=split(' ',$record);
        ($prefix,$name_string)=split('/',$board_no);
        if ($io_type=~/pcix/) {
          $io_type="PCIX";
        }
        else {
          $io_type="PCI";
        }
      }
    }
    if ($sys_arch=~/480|490|280/) {
      if ($record=~/Schizo/) {
        $tester=1; $io_type="pci";
        ($name_string,$port_id,$status,$device_rev)=split(' ',$record);
      }
    }
    if ($sys_arch=~/880|890/) {
      if ($record=~/IB/) {
        $tester=1;
        ($name_string,$prefix,$port_id,$status,$device_rev)=split(' ',$record);
      }
    }
    if ($sys_arch=~/Ultra-5_10/) {
      if ($record=~/Cheerio/) {
        $tester=1;
        ($name_string,$io_type,$prefix,$device_rev)=split(' ',$record);
      }
    }
    if ($sys_arch=~/Ultra-60/) {
      if ($record=~/Cheerio|PCI|FEPS/) {
        $tester=1;
        ($name_string,$io_type,$prefix,$device_rev)=split(' ',$record);
      }
    }
    if ($sys_arch=~/Ultra-4|Sun-Blade-100|Ultra-250/) {
      if ($record=~/Rev /) {
        $tester=1;
        ($name_string,$prefix,$device_rev)=split(' ',$record);
      }
    }
    if (($sys_arch=~/Ultra-Enterprise/)&&($sys_arch!~/10000/)) {
      if ($record=~/Dual\-SBus/) {
        $tester=1;
        ($board_no,$fhc_no,$ac_voltage,$sbus_one,$sbus_two,$feps_no,$name_string,$capspd,$prefix)=split(' ',$record);
      }
      if ($record=~/CPU/) {
        $tester=1; $feps_no="";
        ($board_no,$fhc_no,$ac_voltage,$name_string,$capspd,$prefix)=split(' ',$record);
      }
    }
    if ($name_string=~/\:$/) {
      $name_string=~s/\:$//g;
    }
    if (($name_string!~/[A-z]/)&&($name_string!~/[0-9]/)) {
      $name_string=$na_string;
    }
    if (($board_no!~/[A-z]/)&&($board_no!~/[0-9]/)) {
      $board_no=$na_string;
    }
    if (($fhc_no!~/[A-z]/)&&($fhc_no!~/[0-9]/)) {
      $fhc_no=$na_string;
    }
    if (($feps_no!~/[A-z]/)&&($feps_no!~/[0-9]/)) {
      $feps_no=$na_string;
    }
    if (($io_type!~/[A-z]/)&&($io_type!~/[0-9]/)) {
      $io_type=$na_string;
    }
    if (($io_path!~/[A-z]/)&&($io_path!~/[0-9]/)) {
      $io_path=$na_string;
    }
    if (($port_id!~/[A-z]/)&&($port_id!~/[0-9]/)) {
      $port_id=$na_string;
    }
    if (($device_rev!~/[A-z]/)&&($device_rev!~/[0-9]/)) {
      $device_rev=$na_string;
    }
    if (($status!~/[A-z]/)&&($status!~/[0-9]/)) {
      $status=$na_string;
    }
    if ($status=~/ok|online|GOOD/) {
      $status="OK";
    }
    if ($tester eq 1) {
      $hardware_status[$number]="$name_string|$board_no|$fhc_no|$feps_no|$io_type|$io_path|$port_id|$device_rev|$status";
      $number++;
    }
  }
  $tester=0;
  if (($do_list eq 1)||($do_mail eq 1)) {
    if ($verbose eq 1) {
      print "\n";
      print "Hardware Revision Information:\n";
    }
    for ($counter=0;$counter<@hardware_status;$counter++) {
      $record=$hardware_status[$counter];
      ($name_string,$board_no,$fhc_no,$feps_no,$io_type,$io_path,$port_id,$device_rev,$status)=split('\|',$record);
      $output="$name_string $board_no $fhc_no $feps_no $io_type $io_path $port_id $device_rev $status";
      if ($verbose eq 1) {
        print "\n";
        print "\tDevice: $name_string\n";
        print "\tBoard:  $board_no\n";
        print "\tFHC:    $fhc_no\n";
        print "\tFEPS:   $feps_no\n";
        print "\tBus:    $io_type\n";
        print "\tPath:   $io_path\n";
        print "\tPort:   $port_id\n";
        print "\tRev:    $device_rev\n";
        print "\tStatus: $status\n";
      }
      if ($do_mail eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          if ($tester eq 0) {
            print PRTOUT "\n";
            print PRTOUT "Hardware Revision Errors:\n";
            $tester=1;
          }
          $record=~s/NA\||ERROR|\|/ /g;
          print PRTOUT "WARNING: $record\n";
        }
      }
      if ($syslog eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          system("/usr/bin/logger -f $output -p kern.warning");
        }
      }
    }
  }
  return;
}

#
# Process fan information from prtdiag
#

sub process_fan_info {

  my $counter; my $record; my @fan_status; my $tester; my $fan_unit;
  my $status="OK"; my $number=0; my $fan_speed; my $sensor;
  my $fan_tray; my $prefix; my $output;

  for ($counter=0;$counter<@fan_info;$counter++) {
    $tester=0; $fan_unit=""; $status=""; $fan_speed="";
    $sensor=""; $fan_tray=""; $record=$fan_info[$counter];
    chomp($record);
    if ($printr eq 1) {
      print "$record\n";
    }
    if ($sys_arch=~/Sun-Blade-100/) {
      if ($record=~/system/) {
        $tester=1;
        if ($sys_release=~/9|10/) {
          ($prefix,$fan_unit,$status,$fan_speed)=split(' ',$record);
        }
        else {
          ($prefix,$fan_speed)=split(' ',$record);
          $fan_unit="system-fan";
        }
      }
    }
    if (($sys_arch=~/Ultra-Enterprise/)&&($sys_arch!~/10000/)) {
      if ($record=~/^Disk/) {
        $tester=1;
        ($fan_unit,$status)=split(' ',$record);
      }
    }
    if ($sys_arch=~/Ultra-250/) {
      if ($record=~/SYS/) {
        $tester=1;
        ($fan_unit,$fan_speed,$status)=split(' ',$record);
      }
    }
    if ($sys_arch=~/280/) {
      if ($record=~/^FAN/) {
        $tester=1;
        ($fan_unit,$status)=split(' ',$record);
      }
    }
    if ($sys_arch=~/Ultra-4/) {
      if ($record=~/^CPU|^PWR/) {
        $tester=1;
        ($fan_unit,$fan_speed,$status)=split(' ',$record);
      }
    }
    if ($sys_arch=~/480|490/) {
      if ($sys_release=~/8/) {
        if ($record=~/^CPU|^IO/) {
          $tester=1;
          ($fan_unit,$fan_speed,$status)=split(' ',$record);
        }
      }
      if ($sys_release=~/9|10/) {
        if ($record=~/^FAN/) {
          $tester=1;
          ($fan_tray,$fan_unit,$fan_speed,$status)=split(' ',$record);
        }
      }
    }
    if ($sys_arch=~/880|890/) {
      if ($record=~/^CPU|^IO/)  {
        $tester=1;
        ($fan_unit,$fan_speed,$prefix,$status)=split(' ',$record);
      }
    }
    if ($sys_arch=~/240|440|210/) {
      if ($record=~/^MB|^F0|^F1|^F2|^PS|^FT/) {
        $tester=1;
        ($fan_unit,$sensor,$status,$fan_speed)=split(' ',$record);
      }
    }
    if (($fan_unit!~/[A-z]/)&&($fan_unit!~/[0-9]/)) {
      $fan_unit=$na_string;
    }
    if (($fan_speed!~/[A-z]/)&&($fan_speed!~/[0-9]/)) {
      $fan_speed=$na_string;
    }
    if (($status!~/[A-z]/)&&($status!~/[0-9]/)) {
      $status=$na_string;
    }
    if (($sensor!~/[A-z]/)&&($sensor!~/[0-9]/)) {
      $sensor=$na_string;
    }
    if (($fan_tray!~/[A-z]/)&&($fan_tray!~/[0-9]/)) {
      $fan_tray=$na_string;
    }
    if ($status=~/NO_FAULT|ok|online|GOOD/) {
      $status="OK";
    }
    if ($tester eq 1) {
      $fan_status[$number]="$fan_unit|$fan_tray|$fan_speed|$status";
      $number++;
    }
  }
  $tester=0;
  if (($do_list eq 1)||($do_mail eq 1)) {
    if ($verbose eq 1) {
      print "\n";
      print "FAN Information:\n";
    }
    for ($counter=0;$counter<@fan_status;$counter++) {
      $record=$fan_status[$counter];
      ($fan_unit,$fan_tray,$fan_speed,$status)=split('\|',$record);
      $output="$fan_unit $fan_tray $fan_speed $status";
      if ($verbose eq 1) {
        print "\n";
        print "\tUnit:   $fan_unit\n";
        print "\tTray:   $fan_tray\n";
        print "\tSpeed:  $fan_speed\n";
        print "\tStatus: $status\n";
      }
      if ($do_mail eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          if ($tester eq 0) {
            print PRTOUT "\n";
            print PRTOUT "Fan Failures:\n";
            $tester=1;
          }
          $record=~s/NA\||ERROR|\|/ /g;
          print PRTOUT "WARNING: $record\n";
        }
      }
      if ($syslog eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          system("/usr/bin/logger -f $output -p kern.warning");
        }
      }
    }
  }
  return;
}

#
# Process temperature information from prtdiag
#

sub process_temp_info {

  my $counter; my $record; my @temp_status; my $number=0; my $tester;
  my $board_no; my $status="OK"; my $temp_now; my $temp_min; my $temp_max;
  my $temp_trend; my $cpu_one; my $cputwo; my $sensor; my $temp_low;
  my $temp_high; my $prefix; my $output;

  for ($counter=0;$counter<@temp_info;$counter++) {
    $tester=0; $board_no=""; $status=""; $temp_now=""; $temp_min="";
    $temp_max=""; $temp_trend=""; $cpu_one=""; $cputwo=""; $sensor="";
    $temp_low=""; $temp_high=""; $record=$temp_info[$counter];
    chomp($record);
    if ($printr eq 1) {
      print "$record\n";
    }
    if ($sys_arch=~/Sun-Blade-100/) {
      if ($record=~/cpu/) {
        $tester=1;
        ($prefix,$sensor,$temp_now,$temp_min,$temp_low,$temp_high,$temp_max,$status)=split(' ',$record);
        $board_no="$prefix $sensor";
      }
    }
    if (($sys_arch=~/Ultra-Enterprise/)&&($sys_arch!~/10000/)) {
      if ($record=~/[0-9]/) {
        $tester=1;
        ($board_no,$status,$temp_now,$temp_min,$temp_max,$temp_trend)=split(' ',$record);
        $temp_now="$temp_now C"; $temp_min="$temp_min C";
        $temp_max="$temp_max C";
      }
    }
    if ($sys_arch=~/250/) {
      if ($record=~/[0-9]/) {
        $tester=1;
        ($board_no,$temp_now)=split(' ',$record);
      }
    }
    if ($sys_arch=~/280/) {
      if (($record=~/[0-9]/)&&($record!~/cpu0/)) {
        $tester=1;
        ($cpu_one,$cputwo)=split(' ',$record);
        $board_no="CPU0 CPU1";
        $temp_now=" $cpu_one   $cputwo";
      }
    }
    if ($sys_arch=~/450/) {
      if ($record=~/^AMB/) {
        $tester=1;
        ($board_no,$temp_now)=split(' ',$record);
      }
      if ($record=~/^CPU/) {
        $tester=1;
        ($board_no,$prefix,$temp_now)=split(' ',$record);
        $board_no="$board_no $prefix";
      }
    }
    if ($sys_arch=~/240|210/) {
      if ($record=~/^MB|^PS/) {
        $tester=1;
        ($board_no,$sensor,$temp_now,$temp_min,$temp_low,$temp_high,$temp_max,$status)=split(' ',$record);
      }
    }
    if ($sys_arch=~/480|490|880|890/) {
      if ($record=~/^CP|^DB|^MB|^IO/) {
        $tester=1;
        ($board_no,$temp_now,$status)=split(' ',$record);
      }
    }
    if (($board_no!~/[0-9]/)&&($board_no!~/[A-z]/)) {
      $board_no=$na_string;
    }
    if (($status!~/[0-9]/)&&($status!~/[A-z]/)) {
      $status=$na_string;
    }
    if (($sensor!~/[0-9]/)&&($sensor!~/[A-z]/)) {
      $sensor=$na_string;
    }
    if (($temp_now!~/[0-9]/)&&($temp_now!~/[A-z]/)) {
      $temp_now=$na_string;
    }
    if (($temp_min!~/[0-9]/)&&($temp_min!~/[A-z]/)) {
      $temp_min=$na_string;
    }
    if (($temp_low!~/[0-9]/)&&($temp_low!~/[A-z]/)) {
      $temp_low=$na_string;
    }
    if (($temp_high!~/[0-9]/)&&($temp_high!~/[A-z]/)) {
      $temp_high=$na_string;
    }
    if (($temp_max!~/[0-9]/)&&($temp_max!~/[A-z]/)) {
      $temp_max=$na_string;
    }
    if (($temp_trend!~/[0-9]/)&&($temp_trend!~/[A-z]/)) {
      $temp_trend=$na_string;
    }
    if ($status=~/ok|online|GOOD/) {
      $status="OK";
    }
    if ($tester eq 1) {
      $temp_status[$number]="$board_no|$sensor|$temp_now|$temp_low|$temp_min|$temp_high|$temp_max|$temp_trend|$status";
      $number++;
    }
  }
  $tester=0;
  if (($do_list eq 1)||($do_mail eq 1)) {
    if ($verbose eq 1) {
      print "\n";
      print "Temperature Information:\n";
    }
    for ($counter=0;$counter<@temp_status;$counter++) {
      $record=$temp_status[$counter];
      ($board_no,$sensor,$temp_now,$temp_low,$temp_min,$temp_high,$temp_max,$temp_trend,$status)=split('\|',$record);
      $output="$board_no $sensor $temp_now $temp_low $temp_min $temp_high $temp_max $temp_trend $status";
      if ($verbose eq 1) {
        print "\n";
        print "\tBoard:    $board_no\n";
        print "\tSensor:   $sensor\n";
        print "\tCurrent:  $temp_now\n";
        print "\tLow Warn: $temp_low\n";
        print "\tMinimum:  $temp_min\n";
        print "\tHi Warn:  $temp_high\n";
        print "\tMaximum:  $temp_max\n";
        print "\tTrend:    $temp_trend\n";
        print "\tStatus:   $status\n";
      }
      if ($do_mail eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          if ($tester eq 0) {
            print PRTOUT "\n";
            print PRTOUT "Temperature Warnings:\n";
            $tester=1;
          }
          $record=~s/NA\||ERROR|\|/ /g;
          print PRTOUT "WARNING: $record\n";
        }
      }
      if ($syslog eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          system("/usr/bin/logger -f $output -p kern.warning");
        }
      }
    }
  }
  return;
}

#
# Process voltage information from prtdiag
#

sub process_voltage_info {

  my $counter; my $record; my @voltage_status; my $number=0; my $tester;
  my $board_no; my $sensor; my $voltage_now; my $voltage_min; my $voltage_low;
  my $voltage_high; my $voltage_max; my $status="OK"; my $output;

  for ($counter=0;$counter<@volume_info;$counter++) {
    $tester=0; $board_no=""; $sensor=""; $voltage_now="";
    $voltage_min=""; $voltage_low=""; $voltage_high=""; $voltage_max="";
    $status=""; $record=$volume_info[$counter];
    chomp($record);
    if ($printr eq 1) {
      print "$record\n";
    }
    if ($sys_arch=~/210|240|440/) {
      if ($record=~/^MB|^PS/) {
        $tester=1;
        ($board_no,$sensor,$voltage_now,$voltage_min,$voltage_low,$voltage_high,$voltage_max,$status)=split(' ',$record);
      }
    }
    if (($board_no!~/[0-9]/)&&($board_no!~/[A-z]/)) {
      $board_no=$na_string;
    }
    if (($sensor!~/[0-9]/)&&($sensor!~/[A-z]/)) {
      $sensor=$na_string;
    }
    if (($status!~/[0-9]/)&&($status!~/[A-z]/)) {
      $status=$na_string;
    }
    if (($voltage_now!~/[0-9]/)&&($voltage_now!~/[A-z]/)) {
      $voltage_now=$na_string;
    }
    if (($voltage_min!~/[0-9]/)&&($voltage_min!~/[A-z]/)) {
      $voltage_min=$na_string;
    }
    if (($voltage_low!~/[0-9]/)&&($voltage_low!~/[A-z]/)) {
      $voltage_low=$na_string;
    }
    if (($voltage_high!~/[0-9]/)&&($voltage_high!~/[A-z]/)) {
      $voltage_high=$na_string;
    }
    if (($voltage_max!~/[0-9]/)&&($voltage_max!~/[A-z]/)) {
      $voltage_max=$na_string;
    }
    if ($status=~/ok|online|GOOD/) {
      $status="OK";
    }
    if ($tester eq 1) {
      $voltage_status[$number]="$board_no|$sensor|$voltage_now|$voltage_min|$voltage_low|$voltage_high|$voltage_max|$status";
      $number++;
    }
  }
  $tester=0;
  if (($do_list eq 1)||($do_mail eq 1)) {
    if ($verbose eq 1) {
      print "\n";
      print "Voltage Information:\n";
    }
    for ($counter=0;$counter<@voltage_status;$counter++) {
      $record=$voltage_status[$counter];
      ($board_no,$sensor,$voltage_now,$voltage_min,$voltage_low,$voltage_high,$voltage_max,$status)=split('\|',$record);
      $output="$board_no $sensor $voltage_now $voltage_min $voltage_low $voltage_high $voltage_max $status";
      if ($verbose eq 1) {
        print "\n";
        print "\tBoard:    $board_no\n";
        print "\tSensor:   $sensor\n";
        print "\tCurrent:  $voltage_now\n";
        print "\tLow Warn: $voltage_low\n";
        print "\tMinimum:  $voltage_min\n";
        print "\tHi Warn:  $voltage_high\n";
        print "\tMaximum:  $voltage_max\n";
        print "\tStatus:   $status\n";
      }
      if ($do_mail eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          if ($tester eq 0) {
            print PRTOUT "\n";
            print PRTOUT "Voltage Warnings:\n";
            $tester=1;
          }
          $record=~s/NA\||ERROR|\|/ /g;
          print PRTOUT "WARNING: $record\n";
        }
      }
      if ($syslog eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          system("/usr/bin/logger -f $output -p kern.warning");
        }
      }
    }
  }
  return;
}

#
# Process current information from prtdiag
#


sub process_current_info {

  my $counter; my $record; my @current_status; my $number=0; my $tester;
  my $board_no; my $sensor; my $current_now; my $current_min; my $current_low;
  my $current_high; my $current_max; my $status=""; my $output; my $current;

  for ($counter=0;$counter<@current_info;$counter++) {
    $tester=0; $board_no=""; $sensor=""; $current="";
    $current_min=""; $current_low=""; $current_high=""; $current_max="";
    $status=""; $record=$current_info[$counter];
    chomp($record);
    if ($printr eq 1) {
      print "$record\n";
    }
    if ($sys_arch=~/210|240|440/) {
      if ($record=~/^MB|^PS|^C[0-9]/) {
        $tester=1;
        ($board_no,$sensor,$current_now,$current_min,$current_low,$current_high,$current_max,$status)=split(' ',$record);
      }
    }
    if (($board_no!~/[0-9]/)&&($board_no!~/[A-z]/)) {
      $board_no=$na_string;
    }
    if (($sensor!~/[0-9]/)&&($sensor!~/[A-z]/)) {
      $sensor=$na_string;
    }
    if (($status!~/[0-9]/)&&($status!~/[A-z]/)) {
      $status=$na_string;
    }
    if (($current!~/[0-9]/)&&($current!~/[A-z]/)) {
      $current=$na_string;
    }
    if (($current_min!~/[0-9]/)&&($current_min!~/[A-z]/)) {
      $current_min=$na_string;
    }
    if (($current_low!~/[0-9]/)&&($current_low!~/[A-z]/)) {
      $current_low=$na_string;
    }
    if (($current_high!~/[0-9]/)&&($current_high!~/[A-z]/)) {
      $current_high=$na_string;
    }
    if (($current_max!~/[0-9]/)&&($current_max!~/[A-z]/)) {
      $current_max=$na_string;
    }
    if ($status=~/ok|online|GOOD/) {
      $status="OK";
    }
    if ($tester eq 1) {
      $current_status[$number]="$board_no|$sensor|$current|$current_min|$current_low|$current_high|$current_max|$status";
      $number++;
    }
  }
  $tester=0;
  if (($do_list eq 1)||($do_mail eq 1)) {
    if ($verbose eq 1) {
      print "\n";
      print "Current Information:\n";
    }
    for ($counter=0;$counter<@current_status;$counter++) {
      $record=$current_status[$counter];
      ($board_no,$sensor,$current_now,$current_min,$current_low,$current_high,$current_max,$status)=split('\|',$record);
      $output="$board_no $sensor $current $current_min $current_low $current_high $current_max $status";
      if ($verbose eq 1) {
        print "\n";
        print "\tBoard:    $board_no\n";
        print "\tSensor:   $sensor\n";
        print "\tCurrent:  $current_now\n";
        print "\tLow Warn: $current_low\n";
        print "\tMinimum:  $current_min\n";
        print "\tHi Warn:  $current_high\n";
        print "\tMaximum:  $current_max\n";
        print "\tStatus:   $status\n";
      }
      if ($do_mail eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          if ($tester eq 0) {
            print PRTOUT "\n";
            print PRTOUT "Current Warnings:\n";
            $tester=1;
          }
          $record=~s/NA\||ERROR|\|/ /g;
          print PRTOUT "WARNING: $record\n";
        }
      }
      if ($syslog eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          system("/usr/bin/logger -f $output -p kern.warning");
        }
      }
    }
  }
  return;
}

#
# Process power information from prtdiag
#

sub process_power_info {

  my $counter; my $record; my @power_status; my $number=0; my $tester;
  my $power_supply; my $status="OK"; my $power_rating; my $power_temp;
  my $model_info; my $output;

  for ($counter=0;$counter<@power_info;$counter++) {
    $tester=0; $power_supply=""; $status=""; $power_rating="";
    $power_temp=""; $model_info=""; $record=$power_info[$counter];
    chomp($record);
    if ($printr eq 1) {
      print "$record\n";
    }
    if (($sys_arch=~/Ultra-Enterprise/)&&($sys_arch!~/10000/)) {
      if (($record!~/^--/)&&($record!~/^Supply|^Power|^$/)) {
        $tester=1;
        ($power_supply,$status)=split(' ',$record);
      }
    }
    if ($sys_arch=~/250|480|490|880|890/) {
      if ($record=~/^PS/) {
        $tester=1;
        ($power_supply,$status)=split(' ',$record);
      }
    }
    if ($sys_arch=~/280/) {
      if ($record=~/[0-9]/) {
        $tester=1;
        ($power_supply,$status,$model_info)=split(' ',$record);
      }
    }
    if ($sys_arch=~/450/) {
      if ($record=~/[0-9]/) {
        $tester=1;
        ($power_supply,$power_rating,$power_temp,$status)=split(' ',$record);
      }
    }
    if (($power_supply!~/[A-z]/)&&($power_supply!~/[0-9]/)) {
      $power_supply=$na_string;
    }
    if (($status!~/[A-z]/)&&($status!~/[0-9]/)) {
      $status=$na_string;
    }
    if (($power_rating!~/[A-z]/)&&($power_rating!~/[0-9]/)) {
      $power_rating=$na_string;
    }
    if (($power_temp!~/[A-z]/)&&($power_temp!~/[0-9]/)) {
      $power_temp=$na_string;
    }
    if ($status=~/NO_FAULT|ok|online|GOOD/) {
      $status="OK";
    }
    $model_info=~s/\[//g; $model_info=~s/\]//g;
    if ($tester eq 1) {
      $power_status[$number]="$power_supply|$power_rating|$power_temp|$model_info|$status";
      $number++;
    }
  }
  $tester=0;
  if (($do_list eq 1)||($do_mail eq 1)) {
    if ($verbose eq 1) {
      print "\n";
      print "Power Information:\n";
    }
    for ($counter=0;$counter<@power_status;$counter++) {
      $record=$power_status[$counter];
      ($power_supply,$power_rating,$power_temp,$model_info,$status)=split('\|',$record);
      $output="$power_supply $power_rating $power_temp $model_info $status";
      if ($verbose eq 1) {
        print "\n";
        print "\tSupply: $power_supply\n";
        print "\tRating: $power_rating\n";
        print "\tTemp:   $power_temp\n";
        print "\tModel:  $model_info\n";
        print "\tStatus: $status\n";
      }
      if ($do_mail eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          if ($tester eq 0) {
            print PRTOUT "\n";
            print PRTOUT "Power Failures:\n";
            $tester=1;
          }
          $record=~s/\[//g;
          $record=~s/NA\||ERROR|\|/ /g;
          $record=~s/NO/ERROR/g;
          print PRTOUT "WARNING: $record\n";
        }
      }
      if ($syslog eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          system("/usr/bin/logger -f $output -p kern.warning");
        }
      }
    }
  }
  return;
}

#
# Process disk information from prtdiag
#

sub process_disk_info {

  my $counter; my $record; my @disk_status; my $number=0; my $tester;
  my $disk_no; my $disk_one; my $disk_two; my $disk_three; my $status_one;
  my $status_two; my $status_three; my $status="OK"; my $prefix; my $output;

  for ($counter=0;$counter<@disk_info;$counter++) {
    $tester=0; $disk_no=""; $disk_one=""; $disk_two="";
    $disk_three=""; $status=""; $status_one=""; $status_two="";
    $status_three=""; $record=$disk_info[$counter];
    chomp($record);
    if ($printr eq 1) {
      print "$record\n";
    }
    $record=~s/\[ ON\]/\[ON\]/g;
    if ($sys_arch=~/250/) {
      if ($record=~/DISK/) {
        $tester=1;
        ($prefix,$disk_one,$status_one,$prefix,$disk_two,$status_two,$prefix,$disk_three,$status_three)=split(' ',$record);
        $disk_no="$disk_one $disk_two $disk_three";
        $status="$status_one $status_two $status_three";
      }
    }
    if ($sys_arch=~/280/) {
      if ($record=~/DISK/) {
        $tester=1;
        ($prefix,$disk_no,$prefix,$status)=split(' ',$record);
      }
    }
    if ($sys_arch=~/480|490/) {
      if ($record=~/DISK/) {
        $tester=1;
        ($prefix,$disk_no,$status)=split(' ',$record);
      }
    }
    if ($sys_arch=~/880|890/) {
      if (($record=~/DISK/)&&($record!~/EMPTY/)) {
        $tester=1;
        ($prefix,$disk_no,$prefix,$status)=split(' ',$record);
      }
    }
    if ($sys_arch=~/450/) {
      if ($record=~/DISK/) {
        $tester=1;
        ($prefix,$disk_one,$status_one,$prefix,$disk_two,$status_two)=split(' ',$record);
        $disk_no="$disk_one $disk_two"; $status="$status_one $status_two";
      }
    }
    if (($status!~/[0-9]/)&&($status!~/[A-z]/)) {
      $status=$na_string;
    }
    if (($disk_no!~/[0-9]/)&&($disk_no!~/[A-z]/)) {
      $disk_no=$na_string;
    }
    if ($disk_no!~/DISK/) {
      $disk_no="DISK $disk_no";
    }
    $status=~s/\[//g; $status=~s/\]//g;
    $status=~s/NO_FAULT/OK/g; $status=~s/EMPTY/NA/g;
    $status=~s/OFF/OK/g; $status=~s/GOOD/OK/g;
    $status=~s/ON/ERROR/g;
    if ($tester eq 1) {
      $disk_status[$number]="$disk_no|$status";
      $number++;
    }
  }
  $tester=0;
  if (($do_list eq 1)||($do_mail eq 1)) {
    if ($verbose eq 1) {
      print "\n";
      print "Disk Information:\n";
    }
    for ($counter=0;$counter<@disk_status;$counter++) {
      $record=$disk_status[$counter];
      ($disk_no,$status)=split('\|',$record);
      $output="$disk_no $status";
      if ($verbose eq 1) {
        print "\n";
        print "\tDisk:   $disk_no\n";
        print "\tStatus: $status\n";
      }
      if ($do_mail eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          if ($tester eq 0) {
            print PRTOUT "\n";
            print PRTOUT "Disk Failures:\n";
            $tester=1;
          }
          $record=~s/NA\||ERROR|\|/ /g;
          print PRTOUT "WARNING: $record\n";
        }
      }
      if ($syslog eq 1) {
        if ($status!~/OK|$na_string|GOOD/) {
          system("/usr/bin/logger -f $output -p kern.warning");
        }
      }
    }
  }
  return;
}

#
# Mail a report if errors are found
#

sub mail_report {

  my $length=`wc -l $prtdiag_output |awk '{print \$1}'`;
  my $tester;

  chomp($length);
  if ($length!~/^0$/) {
    if ($option{'t'}) {
      system("cat $prtdiag_output |/usr/bin/mailx -s \"$script_name $hostname System Failures\" $sys_admin");
      return;
    }
    if (!$option{'e'}) {
      if (-e "$date_file") {
        $tester=`diff $prtdiag_output $date_file`;
        if ($tester=~/[A-z]/) {
          system("rm $date_file");
        }
      }
      if (! -e "$date_file") {
        system("touch $date_file");
        system("cat $prtdiag_output |/usr/bin/mailx -s \"$script_name $hostname System Failures\" $sys_admin");
        system("cp $prtdiag_output $date_file");
      }
    }
    else {
      system("cat $prtdiag_output");
    }
  }
  else {
    if ($option{'e'}) {
      print "No Failures\n";
    }
  }
  return;
}

#
# Clean up any temporary files
#

sub remove_temp_file {
  if (-e "$prtdiag_output") {
    close PRTOUT;
    system("rm $prtdiag_output");
  }
  return;
}

