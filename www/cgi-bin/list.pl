#!/usr/bin/perl

use warnings;
use strict;
use CGI qw ( -no_xhtml :standart );
use DBI;
use DBD::mysql;

my $script_dir = '/cgi-bin/';
my $script_name = 'list.pl';
my $db_name = 'cosa';
my $db_user = 'cosa_user';
my $db_passwd = 'cosa_passwd';
my $db_host = 'localhost';
my $db_port = '3306';
my $ds = "DBI:mysql:$db_name:$db_host:$db_port";
my $table = 'hosts';

my $q = CGI->new();

print <<END;
Content-Type: text/html; charset=utf-8

<!DOCTYPE html>
<html lang='en'>
  <head>
    <title>R5000 Devices List</title>
    <meta refresh='86400'>
    <link rel="stylesheet" href="http://172.27.65.94/style.css">
  </head>
  <body>
END

my $dbh = DBI->connect( $ds, "$db_user", "$db_passwd", {RaiseError => 1} ) or die $DBI::errstr;
my ( $addr, $pass, $is_bs, $descr, $date );

if (defined $q->param( 'button_delete' )) {
		my $addr = $q->param( 'grp_addr' );
        my $del_query = "DELETE FROM $table WHERE addr=".$dbh->quote($addr);
        $dbh->do( $del_query );
		print '<script type="text/javascript">location.replace("list.pl");</script>';
}
elsif ( defined $q->param( 'button_add' ) ) {
        $addr = $dbh->quote( $q->param( 'input_host' ) );
        $pass = $dbh->quote( $q->param( 'input_pass' ) );
        
		if (defined $q->param( 'button_bs' )) {
			$is_bs = 1;
		} else {
			$is_bs = 0;
		}
        $descr =$dbh->quote( $q->param( 'input_descr' ) );
        $dbh->do( "INSERT INTO $table( addr,pass,bs,description ) VALUES ( $addr,$pass,$is_bs,$descr )" );
        print '<script type="text/javascript">location.replace("list.pl");</script>';
}

# select rows from database
my $qh = $dbh->prepare( "SELECT addr, pass, bs, description, date FROM $table ORDER BY bs,addr" );
$qh->execute() or die $qh->errstr;

print "<a href=$script_dir"."params-mysql.pl>Parameters</a> <a href=$script_dir"."configs.pl>Configs</a> <b><a href=$script_dir"."list.pl>Devices List</a></b>\n";

print <<"(HTML)";
 <script type="text/javascript">
        function enableDelButton() {                                                                                                                                                 
                document.getElementById("button_delete").disabled = false;                                                                                                              
        }

        function checkAddInput() {
                var a =  document.forms["list-add"]["input_host"].value;
                var b =  document.forms["list-add"]["input_pass"].value; 
                var ena = true;

                if(a.length > 0) {
                        if (a.indexOf(' ') >= 0) {
                                alert("Hostname cannot have spaces in them");
                                ena = false;
                        }
                } else {ena = false;  };

                if(b.length > 0) {
                        if (b.indexOf(' ') >= 0) {
                                alert("Password cannot have spaces in them");
                                ena = false;
                        }
                } else {ena = false;  };

                document.getElementById("button_add").disabled = !ena;
        }

        function getCheckedValue(radioObj) {
                if(!radioObj)
                        return "";
                var radioLength = radioObj.length;
                if(radioLength == undefined)
                        if(radioObj.checked)
                                return radioObj.value;
                        else
                                return "";
                for(var i = 0; i < radioLength; i++) {
                        if(radioObj[i].checked) {
                                return radioObj[i].value;
                        }
                }
                return "";
        }

        function delete_host() {
                var selected_host = getCheckedValue(document.forms['list-del'].elements['grp_addr']);
                var answer = confirm ('Delete the '+selected_host+'?')
                return answer;
        }

         function add_host() {
            //    var addr = document.forms['list-add'].elements['input_host'].value;
            //   var pass = document.forms['list-add'].elements['input_pass'].value;
            //    var bs = 1;
            //    var descr = document.forms['list-add'].elements['input_descr'].value;
            //    if (document.forms['list-add'].elements['button_bs'].checked) {
            //            bs = 1;
            //    }
            //    else {bs = 0}
            //    parent.location='list.pl?action=add&addr='+addr+'&pass='+pass+'&is_bs='+bs+'&descr='+descr;
        }
</script>

<table>
<tr>
<td valign="top">
<form method="post" enctype="application/x-www-form-urlencoded" name="list-del"  onsubmit="return delete_host();">
<table border="0">
<tr>
<td>
<table border="1" cellpadding="3">
        <th><b></b></th>
        <th><b>Host</b></th>
        <th><b>is_bs</b></th>
        <th><b>Description</b></th>
        <th><b>Date</b></th>
(HTML)

$qh->bind_columns( undef, \$addr, \$pass, \$is_bs, \$descr, \$date );
while( $qh->fetch() ) {
        print "<tr><td><INPUT TYPE=\"radio\" NAME=\"grp_addr\" VALUE=\"$addr\" onClick=\"enableDelButton();\"></td><td>$addr</td><td align=\"center\">$is_bs</td><td>$descr</td><td>$date</td></tr>\n";
}
print '</table>';
print '<INPUT TYPE="submit" NAME="button_delete" VALUE="Del" ID="button_delete" disabled="true">';
print $q->end_form();
print '</td>';

print <<"(HTML)";
<td valign="top">
<form method="post" enctype="application/x-www-form-urlencoded" name="list-add">
        <INPUT TYPE="text" NAME="input_host" ID="input_host" onChange="checkAddInput();" placeholder="172.18.0.1" size='30' autofocus required><label for="input_host"> Host</label><br>
        <INPUT TYPE="text" NAME="input_pass" ID="input_pass" onChange="checkAddInput();" placeholder="AB BS LN or your password" size='30' required><label for="input_pass"> Password</label><br>
        <INPUT TYPE="text" NAME="input_descr" ID="input_description" placeholder="Здесь можно что-то написать" size='30'><label for="input_description"> Description</label><br>
        <INPUT TYPE="checkbox" NAME="button_bs" ID="button_bs" VALUE="1" CHECKED="true"><label for="button_bs">BS</label><br>
        <INPUT TYPE="submit" NAME="button_add" ID="button_add" VALUE="Add" disabled="true" onClick="add_host();"><br>
</form>
</td>
</tr>
</table>
(HTML)

$qh->finish();
print $q->end_html();

