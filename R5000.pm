#!/usr/bin/perl

# Module for Infinet Wireless Skyman (R5000) devices

# Sample Usage:
# my $host = R5000->connect(
#     hostname      => $host_ip,
#     type          => 'BS',
#     timeout       => 15,
#     passwords     => \@passwords,
#     error_handler => \&connectErrorHandler,
# );

# $host->login($user, $pass) or die "login to $host_ip FAIL\n";
# %info = %{$host->getInfo()};
# @neighbors_ip = $host->getNeighbors();
# $host->saveChanges();
# $host->close();
#
# sub connectErrorHandler {
#     my $h = shift;            # Host
#     my $t = ${\shift()};      # Net::Telnet object
#     my $error = $t->errmsg(); # Error Message
#     $t->close;
#     die "$h - $error";
# }

package R5000;

use warnings;
use strict;
use Net::Telnet;
use English qw(-no_match_vars);
use Exporter;
use vars qw( @ISA @EXPORT );

@ISA = ('Exporter');
@EXPORT = qw(&compareMintVer);

our $VERSION = '1.0';

# Flush after every write
local $OUTPUT_AUTOFLUSH = 1;

my $prompt       = '#[0-5]>';         # приглашение для ввода команды
my $user_regex   = '/Login:.*$/i';    # регулярное выражение ввода логина
my $pass_regex   = '/Password:.*$/i'; # регулярное выражение ввода пароля
my $pass_fail    = 'Sorry';
my $pass_timeout = '8';

sub connect {
    my $class = shift();
    my $self = {
        @_
    };

    $self->{t} = Net::Telnet->new(
        Timeout => $self->{timeout},
        Prompt => "/$prompt/",
    );

    my $t = $self->{t};

    $t->cmd_remove_mode(1);
    $t->max_buffer_length('512000'); # Максимальный размер буфера в байтах

    if (defined($self->{error_handler})) {
        my @error_array = ($self->{error_handler}, $self->{hostname}, $self->{t});
        $t->errmode( \@error_array );
    }

    bless($self, $class);
    return $self;
}

sub login {
    my $self = shift();
    my $user = shift();
    my $pass = shift();
    my $t = $self->{t};
    my $h = $self->{hostname};
    my @p = @{$self->{passwords}};
    my $login_successfull = 0;

    if( !$t->open($h) ) {
        return 0;
    }

    $t->waitfor($user_regex);
    $t->print($user);
    $t->waitfor($pass_regex);
    $t->print($pass);

    my ($prematch, $match) = $t->waitfor( Match => "/$prompt|$pass_fail/i", Timeout => $pass_timeout );

    if ($match eq $pass_fail) {
        for (@p) {
            if ($_ eq $pass) { next; };
            $t->waitfor($user_regex);
            $t->print($user);
            $t->waitfor($pass_regex);
            $t->print($_);

            my ($prematch, $match) = $t->waitfor( Match => "/$prompt|$pass_fail/i", Timeout => $pass_timeout );

            if ($match ne $pass_fail) {
                $login_successfull = 1;
                last;
            }
        }
    } else {
        $login_successfull = 1;
    }

    if ($login_successfull) {
        changeWindowSize($t);
        return 1;
    }
    return 0;
}

sub getInfo {
    my $self = shift();
    my $t = $self->{t};

    my %info;

    my ( $config, $name, $ver, $sn, $freq, $bitr, $sid, $pwr, $dist, $band, $rf_ip, $rf_prefix  );
    my ( $rf_mac, $mimo, $polling, $roaming, $rf_ospf_area, $rf_ospf_auth, $uptime, );
    my ( $lic, $lic_type, $rid, $pwr_max, $bitr_max, $gps, $update_time );

    # получение текущего времени
    my($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);
    $mon = sprintf('%02d', ++$mon);
    $mday = sprintf('%02d', $mday);
    $year += '1900';                   # localtime возвращает последние 2 цифры года
    $update_time = "$year-$mon-$mday";

    # Получение всего конфига
    my @conf_show_out = $t->cmd ('conf show');
    $config = join('', @conf_show_out);

    # получение имени устройства (в версиях MINT, начиная с 1.73.3 команда "sys name"
    # не возвращает имя устройства, а удаляет его из конфига)
    if ($config =~ /sys name (.*)\s/i) {
        $name = $1;
    }

    # получение версии и серийного номера
    my $version_line = $conf_show_out[0];
    if ( $version_line =~ /R5000\s+WANFleX\s+(.+?)\s+\*.*SN:(\d+)/i ) {
        $ver = $1;
        $sn = $2;
    } else {
        print "Error getting wanflex version. Regexp FAIL\n";
    }

    # получение версии радиоинтерфейса
    my $rf_ver;
    if ( $config =~ /rf\s+rf(\d\.\d)/ ) {
        $rf_ver = $1;
    } else {
        print "Error getting rf version. Regexp FAIL\n";
    }

    # получение параметров радиоинтерфейса
    # получение частоты, битрейта, sid, мощности и дистанции
    if ( $config =~ /rf\s+rf\d\.\d\s+freq (\d+) bitr (\d+) sid (.+) .*\n.*(?:pwr|txpwr) (\d+\.?\d?).*distance (auto\(\d+\)|\d+)\s/i ) {
        $freq = $1;
        $bitr = $2;
        $sid = $3;

        # После MINTv1.72.16 мощность стала отображаться в dBm, а не в mWt
        if (compareMintVer($ver,'MINTv1.72.16')){
            $pwr = "$4 dBm";
        } else {
            $pwr = "$4 mWt";
        }

        $dist = $5;
    } else {
        print "Error getting freq, bitr, sid, pwr, dist. Regexp FAIL\n";
    }

    # получение ширины спектра
    $band = '20';
    if ( $config =~ /rf\s+rf\d\.\d\s+band\s+(5|10|20|40|half|quarter|double)/i ) {
        $band = $1;
        if ($band eq 'quarter') { $band = '5';  };
        if ($band eq 'half')    { $band = '10'; };
        if ($band eq 'double')  { $band = '40'; };
    }

    # получение максимальной пропускной способности устройства и мощности
    my @ifcap_out = $t->cmd ("rf rf$rf_ver cap");
    my $ifcap_str = join('', @ifcap_out);

    if ( $ifcap_str =~ /Power levels \(mW\):.*(\b\d+\b)/i ) {
        $pwr_max = "$1 mWt";
    } elsif ($ifcap_str =~ /Power levels \(dBm\).*max (\d+)/i) {
        $pwr_max = "$1 dBm";
    } else {
        $pwr_max = 'fail';
    }

    $ifcap_str =~ s/\n//g;

    # Показываем максимальный битрейт на ширине пропускания 20 Мгц 
    if ( $ifcap_str =~ /, (\d+)\s+(?:Modulation types|Crypto algorithms|Frequency bounds)/i ) {
        $bitr_max = $1;

        if (($band eq '5') || ($band eq 'quarter')) {
            $bitr_max *= 4;
        } elsif (($band eq '10') || ($band eq 'half')) {
            $bitr_max *= 2;
        } elsif (($band eq '40') || ($band eq 'double')) {
            $bitr_max /= 2;
        }
    } else {
        print "Max Bitrate fail\n";
    }

    # получение ip адреса и префикса радио интерфейса
    my @ifc_out = $t->cmd ("ifconfig rf$rf_ver");
    my $ifc_str = join('', @ifc_out);

    if ( $ifc_str =~ /inet (\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b) netmask 0x([0-9a-f]{8})/i ) {
        $rf_ip = $1;
    } else {
        $rf_ip = '';
    }

    if ( $ifc_str =~ /netmask 0x([0-9a-f]{8})/i ) {
        $rf_prefix = hex2prefix($1);
    } else {
        $rf_prefix = '';
    }
    $rf_ip = "$rf_ip\/$rf_prefix";

    # получение mac адреса радио интерфейса
    $rf_mac = getMac($t, $rf_ver);

    # поддержка MIMO    
    if ( $config =~ /rf rf5.0/ ) {
        $mimo = 1;
    } else {
        $mimo = 0;
    }

    # включен ли поллинг
    if ( $config =~ /(mint|rma)\s+rf\d\.\d\s+poll/ ) {
        $polling = 1;
    } else {
        $polling = 0;
    }

    # включен ли роуминг
    if ( $config =~ /mint\s+rf\d\.\d\s+-roaming\s+(enable|leader)/ ) {
        my $roaming_type = $1;
        if ( $roaming_type eq 'enable' ) {
            $roaming = 'R';
        } elsif ( $roaming_type eq 'leader' ) {
            $roaming = 'L';
        }
    } else {
        $roaming = '0';
    }

    # получение номера OSPF области и аутентификации на радиоинтерфейсе
    if ($config =~ /ospf\s+auto-interface\s+rf$rf_ver\s+area\s+(\d+)\.(\d+)\.(\d+)\.(\d+)\n/i) {
        my $octet1 = $1;
        my $octet2 = $2;
        my $octet3 = $3;
        my $octet4 = $4;

        $rf_ospf_area = ($octet1 << 24) | ($octet2 << 16) | ($octet3 << 8) | ($octet4);
    } else {
        $rf_ospf_area = '';
    }

    if ($config =~ /(ospf\s+interface\s+rf$rf_ver\s*ospf\s*authentication\s+message-digest\s*ospf\s*message-digest-key.*\s+)/i) {
        $rf_ospf_auth = 'A';
    } else {
        $rf_ospf_auth = '0';
    }

    if ($config =~ /ospf\s+router-id\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/i) {
        $rid = $1;
    } else {
       $rid = '';
    }

    # получение аптайма
    my @uptime_out = $t->cmd ('sys uptime');
    my $uptime_str = join('', @uptime_out);

    if ( $uptime_str =~ /(?:UP|Uptime:)\s+(.*)\n/i) {
        $uptime = Uptime2secs($1);
    } else {
        $uptime = '-1';
    }

    # получение типа и количества лицензий
    my @lic_out = $t->cmd ('lic --show');
    my $lic_str = join('', @lic_out);

    if ($lic_str =~ /Link: Point to Point/i) {
        $lic_type = 'PtP';
        $lic = 1;
    } elsif ($lic_str =~ /NON-LCCPE/i and $lic_str =~ /Licensed to (\d+) LCPE/i) {
        $lic_type = 'NLCCPE';
        $lic = $1 + 2;
    } elsif ($lic_str =~ /Low Cost CPE/i) {
        $lic_type = 'LCCPE';
        $lic = 0;
    } elsif ($lic_str =~ /PMtP CPE Only/i) {
        $lic_type = 'CPE Only';
        $lic = 1;
    } else {
        $lic_type = '';
        $lic = 0;
    }

    # Получение координат
    if ($config =~ /sys\s+gpsxy\s+(E\d+\.\d+\s+\d+\.\d+)/i) {
        $gps = $1;
    } else {
        $gps = 'E00.000000 N00.000000';
    }

    $info{'name'}         = $name;
    $info{'ver'}          = $ver;
    $info{'sn'}           = $sn;
    $info{'freq'}         = $freq;
    $info{'bitr'}         = $bitr;
    $info{'sid'}          = $sid;
    $info{'pwr'}          = $pwr;
    $info{'dist'}         = $dist;
    $info{'band'}         = $band;
    $info{'rf_ip'}        = $rf_ip;
    $info{'rf_mac'}       = $rf_mac;
    $info{'mimo'}         = $mimo;
    $info{'polling'}      = $polling;
    $info{'roaming'}      = $roaming;
    $info{'rf_ospf_area'} = $rf_ospf_area;
    $info{'rf_ospf_auth'} = $rf_ospf_auth;
    $info{'uptime'}       = $uptime;
    $info{'lic'}          = $lic;
    $info{'lic_type'}     = $lic_type;
    $info{'rid'}          = $rid;
    $info{'pwr_max'}      = $pwr_max;
    $info{'bitr_max'}     = $bitr_max;
    $info{'gps'}          = $gps;
    $info{'update_time'}  = $update_time;

    $self->{ver}          = $ver;
    $self->{config}       = $config;
    $self->{rf_ver}       = $rf_ver;
    $self->{info}         = \%info;

    return $self->{info};
}

# получение версии
sub getVer {
    my $t = ${\shift()};
    my @version = $t->cmd ('sys ver');
    my $version_crop = $version[1];

    if ( $version_crop =~ m/R5000\s+WANFleX\s+(.+?)\s+/i ) {
      return $1;
    }
  return 0;
}

# получение списка соседей
sub getNeighbors {
    my $self = shift();
    my $t = $self->{t};

    my $ver = $self->{ver};

    if (!defined $ver) {
        $ver = getVer($t);
        $self->{ver} = $ver;
    }

    # получение списка соседей в зависимости от версии прошивки
    if ($ver =~ /rma/i || $ver =~ /mini/i) {
        my @rma_ab = getRmaAb($t->cmd ('rma ab'));
        if (@rma_ab) {
            return @rma_ab;
        }
    }

    if ($ver =~ /mint/i) {
        my @mint_ab = getMintAb($t->cmd ('mint map det'));
        if (@mint_ab) {
            return @mint_ab;
        }
    }

    if ($ver =~ /cpe-mesh/i || $ver =~ /avila-MESH/i) {
        my @mesh_ab = getMeshAb($t);
        if (@mesh_ab) {
            return @mesh_ab;
        }
    }

    # Возвращаем пустой массив
    return ();
}

# получение списка клиентов на прошивке RMA
sub getRmaAb {
    my @ab_tmp;
    foreach my $ab (@_) {
        if ($ab =~ /\b(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)->(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/i) {
            push(@ab_tmp, "$1.$2.$3.$5");
        }
    }
    return @ab_tmp;
}

# получение списка клиентов на прошивке MINT
sub getMintAb {
    my @ab_tmp;
    foreach my $ab (@_) {
        if ($ab =~ /\bIP=(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/i) {
            push(@ab_tmp, "$1.$2.$3.$4");
        }
    }
    return @ab_tmp;
}

# получение списка клиентов на прошивках CPE-MESH и avila-MESH
sub getMeshAb {
    my @ab_tmp;
    my @macs;
    my $t = ${\shift()};

    # получение mac адресов соседей по радио
    my @mint_map_out = $t->cmd ('mint map');

    # получение arp таблицы
    my @arp_view_out = $t->cmd ('arp view');

    foreach my $str (@mint_map_out) {
        if ($str =~ /([0-9a-f]{12})/i) {
            push(@macs, "$1");
        }
    }

    # получение ip адресов соседей из arp таблицы
    my %h;
    foreach my $str (@arp_view_out) {
        if ($str =~ /(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}) at ([0-9a-f]{12})/i) {
            $h{"$2"} = "$1";
        }
    }

    foreach my $str (@macs) {
        if (defined($h{$str})) {
            push(@ab_tmp,$h{$str});
        }
    }
    return @ab_tmp;
}

# получение mac адреса радиоинтерфейса
sub getMac {
    my $tt = ${\shift()};
    my $rfrf = ${\shift()};
    my @ifc_out = $tt->cmd ("ifconfig rf$rfrf");
    my $ifc_str = join('', @ifc_out);

    if ($ifc_str =~ /ether ((?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2})/i) {
        return $1;
    } else {
        return '';
    }
}

# Compare two mint versions
sub compareMintVer {
    my $ver1 = $_[0];
    my $ver2 = $_[1];

    if ( $ver1 !~ /.*MINT.*/i || $ver2 !~ /.*MINT.*/i ) { return; };

    my @ver_a1 = (0,0,0);
    my @ver_a2 = (0,0,0);

    if ( $ver1 =~ /.*MINTv(\d+)\.(\d+)\.(\d+).*/i ) {
        $ver_a1[0] = $1;
        $ver_a1[1] = $2;
        $ver_a1[2] = $3;
    } else {
        print "Error getting first version. Regexp FAIL\n";
    }

    if ( $ver2 =~ /.*MINTv(\d+)\.(\d+)\.(\d+).*/i ) {
        $ver_a2[0] = $1;
        $ver_a2[1] = $2;
        $ver_a2[2] = $3;
    } else {
        print "Error getting second version. Regexp FAIL\n";
    }

    if (($ver_a1[1]) > 0 && ($ver_a1[1]) < 10) { $ver_a1[1] *= 10 };
    if (($ver_a1[2]) > 0 && ($ver_a1[2]) < 10) { $ver_a1[2] *= 10 };

    if (($ver_a2[1]) > 0 && ($ver_a2[1]) < 10) { $ver_a2[1] *= 10 };
    if (($ver_a2[2]) > 0 && ($ver_a2[2]) < 10) { $ver_a2[2] *= 10 };

    my $i = 0;
    while ($i < 3) {
        if ($ver_a1[$i] > $ver_a2[$i]) {return 1; }
        elsif ($ver_a1[$i] < $ver_a2[$i]) {return;}
        $i++;
    }

    if ($ver_a1[0] == $ver_a2[0] && $ver_a1[1] eq $ver_a2[1] && $ver_a1[2] eq $ver_a2[2]) {
        return 1;
    };

    return;
}

# префикс из шестнадцатеричной маски
sub hex2prefix {
    my %h2b = (0 => '0000', 1 => '0001', 2 => '0010', 3 => '0011',
        4 => '0100', 5 => '0101', 6 => '0110', 7 => '0111',
        8 => '1000', 9 => '1001', a => '1010', b => '1011',
        c => '1100', d => '1101', e => '1110', f => '1111',
        );

    my $hex = shift;
    ( my $binary = $hex) =~ s/(.)/$h2b{lc $1}/ig;

    return rindex ($binary, '1') + 1;
}

sub Uptime2secs {
    my $uptime = shift;
    my $secs;

    my ($udays, $uhours, $umins, $usecs);

    if ( $uptime =~ /(\d+)+ day/i ) {
        $udays = $1;
    } else { $udays = 0 };

    if ( $uptime =~ /(\d+):(\d+):(\d+)/i ) {
        $uhours = $1;
        $umins  = $2;
        $usecs  = $3;
    } else {
        $uhours = 0;
        $umins  = 0;
        $usecs  = 0;
    }

    $secs = $udays*86400 + $uhours*3600 + $umins*60 + $usecs;
    return $secs;
}

sub saveChanges {
    my $self    = shift();
    my $t       = $self->{t};
    my @out     = $t->cmd ('config save');
    my $out_str = join (' ', @out);

    if ($out_str =~ /Configuration saved successfully/ or $out_str =~ /Ok!/) {
        return 1;
    }

    return 0;
}

sub saveConfigFtp {
    my $ftp_timeout = 70;
    my $self        = shift;
    my $t           = $self->{t};
    my $ver         = $self->{ver};
    my $ftp_IP      = shift;
    my $user_FTP    = shift;
    my $pass_FTP    = shift;
    my $path_FTP    = shift;
    my $name        = shift;

    my @ftp_log = $t->cmd(Timeout => $ftp_timeout, String => 'config export \''."$user_FTP:$pass_FTP\@$ftp_IP$path_FTP$name".'\'');
    my $ftp_log_str = join('', @ftp_log);

    # Обработка результата сохранения
    if ($ftp_log_str =~ /226 .*/i) {
        return 1;
    }

    return 0;
}

sub close {
    my $self = shift();
    my $t    = $self->{t};
    $t->print ('exit');
    $t->close();
    return;
}

# посылаем телнет опцию для изменения максимального размера окна (3070x3070 (0x0b 0xfe))
sub changeWindowSize {
    my $t = ${\shift()};
    my $ors_old = $t->output_record_separator('');
    # сохраняем текущий режим и устанавливаем в 0
    my $otm_old = $t->telnetmode (0);
    $t->binmode(1);
    my $ps = pack( 'CCCCCCCCC', 0xff,0xfa,0x1f,0x0b,0xfe,0x0b,0xfe,0xff,0xf0 );
    # посылаем команду изменения размера окна
    $t->print( $ps );
    $t->output_record_separator($ors_old);
    $t->binmode(0);
    # включаем предыдущий режим
    $t->telnetmode ($otm_old);

    return;
}

sub DESTROY
{
    my $self = shift();
    my $t = $self->{t};
    $t->close();
    undef $t;
    return;
}

return 1;
