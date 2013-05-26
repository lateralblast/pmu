pmu
===

prtdiag Monitoring Utility

The code is rather messy as the prtdiag output on Solaris is
<br />
inconsisted across versions of the OS and versions of hardware
<br />
For example the output for a V480 is different on Solaris 8, 9 and 10.


Usage
-----

	pmu [-][a|e|h|v|c|n] [-l|m][cpu|mem|iod|env|fru|fan|tmp|vol|cur|pwr|dsk|all] [-r][email address] [-][t]

	-l: Display System Information
	-a: Display All System Information
	-m: Mail Failures
	-e: Display Failures
	-h: Display Help
	-v: Display Version
	-c: Display Changelog
	-t: Induce false errors
	-s: Send errors to syslog
	-n: Run without checking for updates
	-r: Alternate recipient to one in code

	-[l|m] cpu:   Process CPU Information
	-[l|m] mem:   Process Memory Information
	-[l|m] iod:   Process IO Information
	-[l|m] env:   Process Environmental Information
	-[l|m] fru:   Process FRU Information
	-[l|m] fan:   Process Fan Information
	-[l|m] tmp:   Process Temperature Information
	-[l|m] vol:   Process Voltage Information
	-[l|m] cur:   Process Current Information
	-[l|m] pwr:   Process Power Information
	-[l|m] dsk:   Process Disk Information
	-[l|m] fma:   Process FMA Information
	-[l|m] all:   Process All Information

Examples
--------

Process all information and email results:

	pmu -m all    

Only display FRU information:

	pmu -l fru   

