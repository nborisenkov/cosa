#!/usr/bin/perl

use warnings;
use strict;
use CGI qw ( -no_xhtml :standart );
use DBI;
use DBD::mysql;
use Time::HiRes qw(gettimeofday);

my $script_dir = '/cgi-bin/';
my $script_name = 'params-mysql.pl';
my $db_name = 'cosa';
my $db_user = 'cosa_user';
my $db_passwd = 'cosa_passwd';
my $db_host = 'localhost';
my $db_port = '3306';
my $ds = "DBI:mysql:$db_name:$db_host:$db_port";
my $table = 'params';
my $configs_dir = 'configs';

my @cols                = ('name', 'freq', 'band', 'sid', 'rf_mac', 'rf_ip', 'rf_ospf_area', 'rf_ospf_auth', 'mimo', 'roaming', 'polling', 'lic_type', 'lic', 'ver',  'rid',  'pwr_max', 'sn', 'bs_sn', 'update_time', 'uptime');
my @cols_captions       = ('name', 'freq', 'band', 'sid', 'rf_mac', 'rf_ip', 'area', 'auth', 'm', 'r', 'p', 'lic_type', 'lic', 'version', 'rid', 'pwr_m', 'sn', 'bs_sn', 'upd_time', 'uptime');
my $qh;
my $color_normal = 'White';
my $color_old = 'Silver';

# get seconds and microseconds since the epoch
my ($s1, $usec1) = gettimeofday();

# get date time
my($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
$mon = sprintf("%02d", ++$mon);
$mday = sprintf("%02d", $mday);
$year += 1900;

my $dbh = DBI->connect($ds, "$db_user", "$db_passwd", {RaiseError => 1}) or die $DBI::errstr; 

# Создаем новый объект CGI
my $q = CGI->new;

# Отправляем заголовок
print $q->header(-type=>'text/html', -charset=>'UTF-8', -refresh=>'3600');

# Выводим заголовок HTML страницы
print $q->start_html( -title => "R5000 Table", -style=>{'src'=>'http://172.27.65.94/style.css'} );

# Ссылки на другие страницы
print "<b><a href=$script_dir"."params-mysql.pl>Parameters</a></b> <a href=$script_dir"."configs.pl>Configs</a> <a href=$script_dir"."list.pl>Devices List</a>\n";

# Выводим заголовок новой формы
print $q->start_form( -name=>"params", -method=>"submit", -action=>$script_name);


my $sortBy_param = $q->param('orderby');
my $sortBy_def = $sortBy_param || 'bs_sn';
my @sortBy = ('name', 'sid','band', 'rf_mac', 'bitr', 'bitr_max', 'rf_ip', 'rf_ospf_area', 'rf_ospf_auth', 'mimo', 'roaming', 'polling', 'lic_type', 'lic', 'ver', 'rid', 'dist', 'pwr', 'pwr_max', 'freq', 'sn', 'bs_sn', 'uptime', 'update_time');
print "Sort by: ";
print "<select name=\"sortBy\" size=\"1\" onChange=\"window.location=document.params.sortBy.options[document.params.sortBy.selectedIndex].value\">\n";
foreach my $key(@sortBy) {
        print "<option value=\"$script_dir$script_name"."?orderby=$key\">$key</option>\n" if $key ne  $sortBy_def;
}
print "<option selected value=\"$sortBy_def\">$sortBy_def</option>\n";
print "</select>\n";

print $q->end_form();
##############################################

my $cols_str = "";
foreach my $key(@cols) {
        $cols_str = "$cols_str$key,";
}
chop $cols_str;

# select rows from database
my $prepare_str = "SELECT $cols_str FROM $table";
if ( defined $sortBy_param)
{
        $prepare_str = "$prepare_str ORDER BY $sortBy_param";
}
else {
         $prepare_str = "$prepare_str ORDER BY bs_sn DESC";
}

$qh = $dbh->prepare("$prepare_str");
$qh->execute() or die $qh->errstr;

# print table header
print "<table border=\"1\">";
print qq(<th><b>#</b></th>);
foreach my $key(@cols_captions) {
        print "<th><b>$key</b></th>";
}

my @row;
my $i = 1;
while (@row = $qh->fetchrow_array) {
        my $row_color;
        my %row_hash;
        @row_hash{@cols} = @row;

        if ($row_hash{'update_time'} ne "$year-$mon-$mday") {
                if ($hour > 12) { $row_color = $color_old }
                else { $row_color = $color_normal }
        }
        else { $row_color = $color_normal };


        my ($cyear, $cmon, $cmday) = split( /-/,$row_hash{'update_time'} );
        $row_hash{'name'}       = "<A HREF=\"/cgi-bin/configs.pl?dir=$cyear.$cmon.$cmday&config=$row_hash{'name'}.cfg.SN-$row_hash{'sn'}\">$row_hash{'name'}</A>\n";
        $row_hash{'uptime'}     = Sec2uptime( $row_hash{'uptime'} );

        print '<tr>';
        print qq(<td BGCOLOR="$row_color">$i</td>);
        foreach my $key(@cols) {
                print qq( <td BGCOLOR="$row_color" NOWRAP><NOBR>$row_hash{$key}</NOBR></td> );
        }
        print '</tr>';
        $i++;
}
print "</table>";
$qh->finish();

# get seconds and microseconds since the epoch
my ($s2, $usec2) = gettimeofday();

my $elapsed_secs = $s2-$s1;
my $elapsed_usecs = $usec2-$usec1;
if ($elapsed_usecs < 0) {$elapsed_usecs += 1000000; $elapsed_secs--}; 

my $elapsed_msecs =  $elapsed_secs*1000+$elapsed_usecs/1000000; 
print "$elapsed_msecs ms<br>";

# Завершающие теги html страницы
print $q->end_html();

####################################################
$dbh-> disconnect();
warn  ($DBI::errstr) if ($DBI::err);

sub Sec2uptime {
        my $secs = shift;
        my $days = 0;
        while ($days*86400 < $secs) {
                $days++;
        }
        $days--;
        $days = 0 if ($days < 0);
        $secs -= $days*86400;

        my $hours = 0;
        while ($hours*3600 < $secs) {
                 $hours++;
        }
        $hours--;
        $hours = 0 if ($hours < 0);
        $secs -= $hours*3600;

        my $mins = 0;
        while ($mins*60 < $secs) {
                $mins++;
        }
        $mins--;
        $mins = 0 if ($mins < 0);
        $secs -= $mins*60;

        my $ret_str = sprintf("%0dd %02d:%02d:%02d",$days, $hours, $mins, $secs);
        return $ret_str;
}
