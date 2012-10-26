#!/usr/bin/perl

use warnings;
use strict;
use CGI qw ( -no_xhtml :standart );

my $conf_dir = '/storage/hd2/cosa/configs';
my $script_dir = '/cgi-bin/';

my $q = CGI->new;
print $q->header(-type=>'text/html', -charset=>'UTF-8', -refresh=>'86400');
print $q->start_html(-title => "R5000 Configs", -style=>{'src'=>'http://172.27.65.94/style.css'} );

print "<a href=$script_dir"."params-mysql.pl>Parameters</a> <b><a href=$script_dir"."configs.pl>Configs</a></b> <a href=$script_dir"."list.pl>Devices List</a>\n";

my $select_dir = $q->param('dir');
my $select_config = $q->param('config');

print $q->start_form( -name=>"configs", -method=>"submit", -action=>"configs.pl");

opendir(IMD, $conf_dir) || die("Cannot open directory");
my @thefiles= readdir(IMD);
closedir(IMD);

my @thefilessort = reverse sort @thefiles;

if (defined($select_dir)) {
        opendir(IMD2, "$conf_dir/$select_dir/") || die ("Error open dir $select_dir : $!\n");
}else {
        opendir(IMD2, "$conf_dir/$thefilessort[0]/") || die ("Error open dir $select_dir : $!\n");
        $select_dir = $thefilessort[0];
}

my @configs = readdir(IMD2);
closedir(IMD2);

@configs = sort @configs;

if (not defined ($select_config)) {
        $select_config = $configs[0];
}

my $i = 0;
while( $select_config eq "."|| $select_config eq ".." ) {
        $select_config = $configs[$i];
        $i++
}

print "<select name=\"dirs\" size=\"1\"onChange=\"window.location=document.configs.dirs.options[document.configs.dirs.selectedIndex].value\">";
foreach my $line (@thefilessort) {
        if ($line ne ".." && $line ne "." && not -d $line)  {
                if (defined($select_dir) && defined($select_config) && $line eq $select_dir)    {
                                print "<option selected value=\"/cgi-bin/configs.pl?dir=$select_dir&config=$select_config\">$line</option>";
                }else {
                        print "<option value=\"/cgi-bin/configs.pl?dir=$line&config=$select_config\">$line</option>\n";
                }
        }
}
print "</select>";

print "<select name=\"files\" size=\"1\"onChange=\"window.location=document.configs.files.options[document.configs.files.selectedIndex].value\">";
foreach my $line (@configs) {
        if ($line ne ".." && $line ne "." && $line ne "ab.txt" && $line ne "bs.txt" && $line && $line ne "muff.txt" && $line ne "bs.xls" && $line ne "all.xls" && $line ne "bs.html" && $line ne "all.html"  ) {
                if (defined($select_dir) && defined($select_config) && $line eq $select_config)         {
                                print "<option selected value=\"/cgi-bin/configs.pl?dir=$select_dir&config=$line\">$line</option>";
                }else {
                        print "<option value=\"/cgi-bin/configs.pl?dir=$select_dir&config=$line\">$line</option>\n";
                }
        }
}
print "</select>";

print " <a href=/configs/$select_dir/$select_config><img src=\"/images/save_as.png\" align=\"bottom\"/><a href=/configs/$select_dir/$select_config>Download</a>";

print $q->end_form();

open (FILE, "$conf_dir/$select_dir/$select_config") ||  die ("Error open file $select_dir/$select_config : $!\n");

while (my $line = <FILE>) {
        print "$line<br>";
}

close (FILE) || die ("Error close file $select_dir/$select_config : $!\n");

print $q->end_html();

