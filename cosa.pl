#!/usr/bin/perl

# Script for configuring Infinet Wireless R5000 (SkyMan) devices

use warnings;
use strict;
use FindBin;
use lib $FindBin::Bin;
use DBI;
use DBD::mysql;
use Net::Telnet;
use Net::SMTP;
use FileHandle;
use File::Path qw(make_path);
use Getopt::Long qw(:config posix_default gnu_getopt no_ignore_case auto_version auto_help);
use English qw(-no_match_vars);
use R5000;

our $VERSION = '1.3';

# Чтение опций запуска
my $test_host = '10.10.10.1';
my $test_mode = 0;
my $verbose   = 0;

sub HelpMessage {
    print "Usage: $PROGRAM_NAME [-v|--verbose] [ -t|--test test_hostname]\n";
    print "Script for configuring Infinet Wireless R5000 (SkyMan) devices\n";
    print "Options:\n";
    print "\t-t, --test\tTest mode. (Connect only to given host) (Default: $test_host)\n";
    print "\t-v, --verbose\tDebug mode. (Be more verbose) (Default: not set)\n";
    print "\t-?, --help\tDisplay this help and exit\n";
    exit;
}

my ( $opt_t );
GetOptions ('test|t:s' => \$opt_t, 'verbose|v' => \$verbose, 'help|?' => sub { HelpMessage() });

print "Starting script...\n" if $verbose;

if (defined $opt_t) {
    if ($opt_t =~ /\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/) {
        $test_host = $opt_t;
        $test_mode = 1;
        $test_host = $opt_t;
    } elsif ($opt_t eq '') {
        $test_mode = 1;
    } else {
        die "$opt_t: not valid ip address for test host\n";
    }
}

print "Setting Test Mode to \"$test_mode\"\n" if $verbose;
print "Setting Test Host to \"$test_host\"\n" if $verbose;

# определение директории где находится скрипт
my $sdir;
if ( $PROGRAM_NAME =~ /^(.+[\\\/])[^\\\/]+[\\\/]*$/ ) {
    $sdir = $1;
} else {
     $sdir = './';
}

# получение текущего времени
my($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);

# текущий месяц и год
$mon = sprintf('%02d', ++$mon);
$mday = sprintf('%02d', $mday);
$year += 1900;     # localtime возвращает последние 2 цифры года

# путь к сегодняшним конфигам
my $path = "/storage/hd2/cosa/configs/$year.$mon.$mday/";
print "Setting path to current configs to \"$path\"...\n" if $verbose;

# создание директории для конфигов, если не существует
if (!-e $path) {
    print "Directory $path does't exist... Create it...\n";
    make_path($path, { verbose => 1 }) || die;
}

# Параметры для подключения к mysql серверу
my $mysql_user        = 'cosa_user';
my $mysql_passwd      = 'cosa_passwd';
my $mysql_host        = 'localhost';
my $mysql_port        = '3306';
my $mysql_db          = 'cosa';

my $mysql_ds          = "DBI:mysql:$mysql_db:$mysql_host:$mysql_port";

my $table             = 'hosts';        # Таблица со списком хостов
my $table_params      = 'params';     # таблица с параметрами оборудования

my $log_file;                           # файл лога

if ($test_mode) {
    $log_file         = "$path".'cosa-test.log';
} else {
    $log_file         = "$path".'cosa.log';
}

print "Set log file to \"$log_file\"\n" if $verbose;

# Соединяемся с MySQL базами данных
print "Connect to mysql databases...\n" if $verbose;

# открытие лог файла
my $log_file_h = FileHandle->new;
$log_file_h->open(">$log_file") || die "Error create file $log_file : $ERRNO\n";
$log_file_h->autoflush(1);

my $ftp_ip          = '10.10.10.2';   # IP адрес FTP
my $ftp_user        = 'cosa';           # логин для FTP сервера
my $ftp_pass        = 'cosa_user';       # пароль для FTP сервера
my $ftp_timeout     = 70;               # Таймаут соединения с FTP сервером (секунд)
my $ftp_path        = "/configs/$year.$mon.$mday/"; # куда сохранять на FTP сервере

my $user            = 'root';     # логин
my $passBS          = '123';     # пароль на БС
my $passAS          = '456';     # пароль на AС
my $passLN          = '769';     # пароль на линк

my $syslog_ip       = '172.20.64.9';    # Адрес syslog сервера
my $sntp_ip         = '172.20.64.9';    # Адрес sntp сервера
my $sntp_interval   = '86400';          # Интервал опроса sntp сервера (секунд)
my $timezone        = 'MSK+4';          # Часовой пояс
my $snmpd_community = 'my-cool-community';     # snmpd community
my $airupdate_mode  = 'passive normal'; # Режим обновления прошивок соседних устройств
my $retries_alert   = '0.4';            # Переповторы больше этого числа будут отправляться на почту

# Список разрешенных адресов для td
my @td_allow  = ('10.10.10.0/24');

# Список возможных паролей на устройства
my @passwords = ("$passAS","$passBS","$passLN");

# Параметры отправки почтовых сообщений
my @alert_emails = ('epic-fail@domain.com'); # Список адресов для предупреждений
my $mail_serv = 'mx.domain.com';             # SMTP сервер
my $mail_from = 'cosa@domain.com';           # Поле письма "От:"

# Устройства с фейлами
my %fails;

my $hosts_ref;

print "Read hosts from database...\n" if $verbose;
$hosts_ref = loadHostsFromDB();

my $dbh = DBI->connect($mysql_ds, "$mysql_user", "$mysql_passwd", {RaiseError => 1}) or die $DBI::errstr;

###########################################################
if ($test_mode) {
    $hosts_ref = [
        {
            addr => $test_host,
            pass => $passBS,
            is_bs => 1,
        }
    ];

    connectToDevices( $hosts_ref );
    #alert_fails();
} else {
    connectToDevices( $hosts_ref );
    print "Sending email with fails...\n" if $verbose;
    alert_fails();
}

print "Done!\n" if $verbose;
##########################################################

$dbh->disconnect();
warn  ($DBI::errstr) if ($DBI::err);

$log_file_h->close;

# Загрузка списка хостов из базы данных
sub loadHostsFromDB {
    my $dbh = DBI->connect($mysql_ds, "$mysql_user", "$mysql_passwd", {RaiseError => 1}) or die $DBI::errstr;
    my $qh_hosts = $dbh->prepare("SELECT addr, pass, bs FROM $table ORDER BY description");
    $qh_hosts->execute() or die $qh_hosts->errstr;

    my $addr;
    my $pass;
    my $is_bs;
    my @hosts;

    $qh_hosts->bind_columns(undef, \$addr, \$pass, \$is_bs);
    while($qh_hosts->fetch()) {
        if ($addr !~ /\b(?:\d{1,3}\.){3}\d{1,3}\b/) {
            print "$addr - not valid ip address\n";
            next;
        }

        my $host = {};
        if ( $pass eq 'AB' ) { $host->{'pass'} = $passAS; }
        elsif ( $pass eq 'BS' ) { $host->{'pass'} = $passBS; }
        elsif ( $pass eq 'LN' ) { $host->{'pass'} = $passLN; }
        else { $host->{'pass'} = $pass; }

        $host->{'is_bs'} = $is_bs;
        $host->{'addr'} = $addr;

        push ( @hosts, $host );
    }

    $qh_hosts->finish();
    $dbh->disconnect();

    warn  ($DBI::errstr) if ($DBI::err);
    return \@hosts;
}

# Подключение к устройству и его настройка
sub connectToDevices {
    my @hosts = @{ $_[0] };
    my $bs_sn =    $_[1];

    if (!defined $bs_sn) {
        $bs_sn = -1;
    }

    my $hosts_count = scalar(@hosts);

    for (my $h = 0; $h < $hosts_count; $h++) {
        my $host_ref = $hosts[$h];
        my $host_ip = $host_ref->{'addr'};
        my $pass = $host_ref->{'pass'};

        print "Connect to \"$host_ip\"...\n" if $verbose;
        my $host = R5000->connect(
            hostname      => $host_ip,
            type          => 'AB',
            timeout       => 15,
            passwords     => \@passwords,
            error_handler => \&connectErrorHandler,
        );

        print "Login to \"$host_ip\"...\n" if $verbose;
        if ( ! $host->login($user, $pass) ) {
            print "login to $host_ip FAIL\n";
            $fails{connect}{$host_ip} = "Login/Password Error";
            next;
        }

        # получение параметров
        print "Get info from \"$host_ip\"...\n" if $verbose;
        my %info = %{$host->getInfo()};

        my $connect_to_neighbors = $host_ref->{'is_bs'};

        # Записываем sn базы в свойства клиента
        if ( $connect_to_neighbors ) {
            $info{'bs_sn'} = $info{'sn'};
        } else {
            $info{'bs_sn'} = $bs_sn;
        }

        # проверка на фейлы
        print "Check fails in \"$host_ip\"...\n" if $verbose;
        check_fails(\$host);

        # добавление параметров в базу данных
        print "Update host info in db...\n" if $verbose;
        my $id = Check_in_db($info{'sn'});
        if ($id > 0) {
            Update_in_db(\%info);
        } else {
            Add_to_db(\%info);
        }

        # Обновление description в таблице hosts
        print "Update host description in db...\n" if $verbose;
        $dbh->do( "UPDATE $table SET description = ".$dbh->quote($info{'name'}).' WHERE addr = '.$dbh->quote($host_ip) );

        # проверка настроек
        print "Check host config...\n" if $verbose;
        checkConfig(\$host);

        # сохранение проделанных изменений
        print "Save changes...\n" if $verbose;
        $host->saveChanges();

        print "Save config to ftp...\n" if $verbose;
        saveConfig(\$host);

        # Прогресс для базовых станций или отдельных железок
        if ( $connect_to_neighbors or $bs_sn eq '-1' ) {
            my $perc = (($h) / $hosts_count) * 100;
            printf ("%s (%.0f%%)\n", $info{name}, $perc);
        } else {
            my $perc = (($h) / $hosts_count) * 100;
            printf ("  %s\n", $info{name});
        }

        # получение списка соседей и их настройка
        if ( $connect_to_neighbors ) {
            print "Get host neighbors...\n" if $verbose;
            my @neighbors_ip = $host->getNeighbors();
            my @neighbors;

            if (scalar(@neighbors_ip) > 0) {
                # Add passwords to host
                for (@neighbors_ip) {
                    my $neighbor_ref = ();
                    $neighbor_ref->{'addr'}  = $_;
                    $neighbor_ref->{'pass'}  = $passAS;
                    $neighbor_ref->{'is_bs'} = '0';
                    push ( @neighbors,  $neighbor_ref);
                }
                print "Connect to host neighbors...\n" if $verbose;
                connectToDevices(\@neighbors, $info{sn});
            }
        }

        # запись в лог файл
        print $log_file_h "$host_ip\tOK\n";
        $host->close();
    }
    return;
}

# сохранение конфига на FTP сервер
sub saveConfig {
    my $host = ${shift()};

    my $filename;
    my $ver  = $host->{info}{ver};
    my $name = $host->{info}{name};
    my $sn   = $host->{info}{sn};

    # для прошивок "-CPE" "avila-MESH" "rma 4.31.0" и "-MINI" добавляем серийный номер к имени файла
    if ($ver =~ /-CPE/ || $ver =~ /RMAv4.31.0/i || $ver =~ /avila-MESH/i || $ver =~ /-MINI/i) {
        $filename = "$name.cfg.SN-$sn";
    } else {
        $filename = "$name.cfg";
    }

    print "Save config to $ftp_ip$ftp_path$filename\n" if $verbose;

    if (! $host->saveConfigFtp($ftp_ip, $ftp_user, $ftp_pass, $ftp_path, $filename)) {
        print "$host->{hostname} - Fail - Error saving config to FTP server. For more information see FTP server logs\n";
        print $log_file_h "$host->{hostname} - Fail - Error saving config to FTP server. For more information see FTP server logs\n";
    }

    return;
}

# проверка настроек
sub checkConfig {
    my $host   = ${shift()};
    my $t      = $host->{t};
    my $ver    = $host->{ver};
    my $rf_ver = $host->{rf_ver};

    # проверка настроек сервиса td
    # пропускаем в тестовом режиме
    print "Checking td config...\n" if $verbose;
    if ( !$test_mode ) {
        checkTD(\$host);
    }

    # включение сервиса snmpd
    print "Enabling SNMPD...\n" if $verbose;
    $t->cmd ('snmpd start');
    $t->cmd ("snmpd community $snmpd_community");

    # отключение сервиса httpd (webcfg)
    print "Disabling webcfg...\n" if $verbose;
    if ($ver =~ /H05/i || $ver =~ /H07/i || $ver =~ /H08/i) {
        $t->cmd ('webcfg stop');
    } else {
        $t->cmd ('httpd stop');
    }

    # Настройка адреса для управления
    # $t->cmd ('ifconfig eth0 192.168.150.81/30 alias');

    # Отключение автоматического обновления прошивки с соседних устройств
    if ($ver =~ /mint/i) {
        $t->cmd("mint rf$rf_ver -mode fixed");
        $t->cmd("mint rf$rf_ver -airupdate $airupdate_mode");
    }

    # отключение отправки redirect icmp сообщений и отбрасывание их
    print "Disabling redirects...\n" if $verbose;
    $t->cmd ('sys nosendredirects');
    $t->cmd ('sys dropredirects');

    # отключение dhcp клиента и релея на eth0
    print "Disabling dhcpc and dhcpr...\n" if $verbose;
    $t->cmd ('dhcpc eth0 stop');
    $t->cmd ('dhcpr stop');

    # установка сервера времени и часового пояса
    print "Setting time server to \"$sntp_ip\"...\n" if $verbose;
    $t->cmd ("sntp -server='$sntp_ip' -interval=$sntp_interval start");
    $t->cmd ("set TZ $timezone");

    # установка сервера логов
    print "Setting syslog server to \"$syslog_ip\"...\n" if $verbose;
    $t->cmd ("sys logging $syslog_ip");

    # сброс статистики переповторов
    print "Clear muff stats...\n" if $verbose;
    $t->cmd ('muff stat clear');

    # Замена "_" в имени на "-"
#    my $name = $host->{info}{name};
#    if ( $name =~ /_/ ) {
#        $_ = $name;
#        tr/_/-/;
#        $name = $_;
#        print "Replace \"_\" in name and promt...\n" if $verbose;
#        $t->cmd("sys name $name");
#        $t->cmd("sys promt $name");
#    }

    return;
}

# проверка настроек сервиса td
sub checkTD {
    my $host   = ${shift()};
    my $config = $host->{config};
    my $t      = $host->{t};
    my @td_enable = ( $config =~ /td\s+enable\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(?:\/\d{1,2})?)/g );

    # цикл по всем td enable на устройстве
    # Удаляем неверные записи
    for (@td_enable) {
        my $td_enable_ip = $_;
        my $del_enable_ip = 1;
        for (@td_allow) {
            my $td_allow_ip = $_;
            if ($td_enable_ip eq $td_allow_ip or $td_enable_ip eq "$td_allow_ip/32") {
                $del_enable_ip = 0;
                next;
            }
        }
        if ($del_enable_ip) {
            $t->cmd("td disable $td_enable_ip");
        }
    }

    # Добавляем нужные записи
    for (@td_allow) {
        my $td_allow_ip = $_;
        if ($config !~ /td\s+enable\s+$td_allow_ip\n/ and $config !~ /td\s+enable\s+$td_allow_ip\/32/) {
            $t->cmd("td enable $td_allow_ip");
        }
    }

    return;
}

# обработка ошибок при подключении и получении информации
sub connectErrorHandler {
    my $h = shift;
    my $t = ${\shift()};
    my $error = $t->errmsg();
    print "$h - Error - $error - For more information see $log_file\n";
    print $log_file_h "$h\tFAIL\t$error\n";
    $fails{connect}{$h} = $error;
    $t->close;
    next;
}

# Проверка существования устройства с sn в базе данных
sub Check_in_db {
    my $sn = shift;
    my $tmp;
    my $qh = $dbh->prepare( "SELECT sn FROM $table_params" );

    $qh->execute() or die $qh->errstr;
    $qh->bind_columns(undef, \$tmp);

    while($qh->fetch()) {
        if ($tmp eq $sn) {
            $qh->finish();
            return $sn;
        }
    }

    $qh->finish();

    return -1;
}

sub Add_to_db {
    my %params = %{shift()};

    my $keys_str   = '';
    my $values_str = '';

    while(my ($key,$value) = each %params){
        $keys_str = qq($keys_str$key ,) ;
        $values_str = qq($values_str'$value' ,);
    };

    chop($keys_str);
    chop($keys_str);

    chop($values_str);
    chop($values_str);

    $dbh->do( qq( INSERT INTO $table_params ( $keys_str ) VALUES ( $values_str ) ) );

    return;
}

sub Update_in_db {
    my %params = %{shift()};

    my $update_query = "UPDATE $table_params SET ";

    while(my ($key,$value) = each %params){
        $update_query=qq($update_query$key='$value', );
    };
 
    chop($update_query);
    chop($update_query);

    $update_query = "$update_query"."WHERE sn='$params{'sn'}'";
    $dbh->do($update_query) or die $dbh->errstr;

    return;
}

# Отправка email с фейлами
sub mail_alert {
    my @emails    = @{shift()};
    my $from_addr = shift;
    my $subject   = shift;
    my $message   = shift;

    # генерация "To: "
    my $to_str = 'To: ';

    for (@emails) {
        my $to_addr = $_;
        $to_str = "$to_str$to_addr, ";
    }

    chop($to_str);
    chop($to_str);

    # Отправка сообщений
    my $smtp = Net::SMTP->new(Host => $mail_serv, Debug => 0);

    if (!defined $smtp) {
        print "FAIL - Error sending email. Use Net::SMTP->new with Debug => 1\n";
        print $log_file_h "FAIL - Error sending email. Use Net::SMTP->new with Debug => 1\n";
    } else {
        for (@emails) {
            my $mail_addr = $_;
            $smtp->mail($from_addr);
            $smtp->to($mail_addr);
            $smtp->data();
            $smtp->datasend("$to_str\n");
            $smtp->datasend("Subject: $subject\n");
            $smtp->datasend("Content-Type: text/html; charset=UTF-8\n");
            $smtp->datasend("\n");
            $smtp->datasend("$message\n\n");
            $smtp->dataend();
        }

        $smtp->quit;
    }

    return;
}

# Проверки на фейлы
sub check_fails {
    my $h       = ${shift()};
    my $t       = $h->{t};
    my $config  = $h->{config};
    my $host    = $h->{hostname};

    my $name;
    if ( $config =~ /sys name (.*)\s/i ) {
        $name = $1;
        if ($name eq 'Unknown node' ) {
            print "Device $host without name!\n";
            $fails{name}{$host} = $name;
        }
    }

    if ( $config =~ /sys user root\n/ ) {
        print "Device $host have default user name!\n";
        $fails{user}{$host} = $name;
    }

    if ( $config =~ /setpass \n/ ) {
        print "Device $host without password!\n";
        $fails{pass}{$host} = $name;
    }

    if ( $config !~ /ifc\s+eth0\s+192.168.150.81\/30/ ) {
        print "Device $host without management ip address!\n";
        $fails{addr}{$host} = $name;
    }

    # Клиенты с переповторами
    my @muff_out = $t->cmd ('muff stat');

    my $muff_regex;
    if (compareMintVer($h->{ver},'MINTv1.72.16')) {
        $muff_regex = '\((\d{1,2}\.\d)\/\d+\/\d+\)\s+\d+\s+(\S+)';
    } else {
        $muff_regex = '[0-9a-f]{12}\s+\d+\/\d+\s+\((\d{1,2}\.\d)\/.*\)\s+(\S+)';
    }

    foreach my $line (@muff_out) {
        if ($line =~ /$muff_regex/i) {
            my $retries_out    = $1;
            my $retries_client = $2;

            if ($retries_out > $retries_alert) {
                print "$name retries > $retries_alert - $retries_client - $retries_out\n";
                $fails{retries}{$host}{name}    = $name;
                $fails{retries}{$host}{retries} = $retries_out;
                $fails{retries}{$host}{client}  = $retries_client;
            }
        }
    }

    # Линк и дуплекс фейл
    if ( $config =~ /ifc.*media.*halfduplex/i ) {
        print "Device $host have interface with half-duplex mode\n";
        $fails{link}{$host} = $name;
    }

    # Железки с mint -type master у которых в соседях есть железка с -type master
    if ( $config =~ /mint/ig ) {
        my @mint_map_det_out = $t->cmd('mint map det');
        my $mint_map_det_str = join('', @mint_map_det_out);
        my $dev_is_master = $mint_map_det_str =~ /,\s+Id\s+\d+,\s+NetId\s+\d+,\s+\(master\)/i;
        my $dev_have_master_neighbor = $mint_map_det_str =~ /\/(M(?:aster)?\/)/i;

        if ( $dev_is_master and $dev_have_master_neighbor ) {
            $fails{master}{$host} = $name;
            print "Device $host have MINT -type Master and clients with -type Master\n";
        }
    }

    return;
}

sub alert_fails {
    # Выйдем если нет фейлов
    my $fails_types_count = scalar(keys %fails);

    if ($fails_types_count == 0) {
        return;
    }

    my $message = "Здравствуйте товарищи!<br>\n<br>\nВысылаю вам подборку очередных фейлов...<br>\n";

    if ( scalar( keys %{$fails{connect}} ) > 0 ) {
        $message  = "$message<br>\n<b>Железки, к которым не удалось подключиться:</b><br>\n";
        while ( my ($host, $error) = each(%{$fails{connect}}) ) {
            $message  = "$message$host - $error<br>\n";
        }
    }

    if ( scalar( keys %{$fails{name}} ) > 0 ) {
        $message  = "$message<br>\n<b>Железки без имени:</b><br>\n";
        while ( my ($host, $name) = each(%{$fails{name}}) ) {
            $message  = "$message$host - $name<br>\n";
        }
    }

    if ( scalar( keys %{$fails{user}} ) > 0 ) {
        $message  = "$message<br>\n<b>Железки c пользователем root:</b><br>\n";
        while ( my ($host, $name) = each(%{$fails{user}}) ) {
            $message  = "$message$host - $name<br>\n";
        }
    }

    if ( scalar( keys %{$fails{pass}} ) > 0 ) {
        $message  = "$message<br>\n<b>Железки без пароля:</b><br>\n";
        while ( my ($host, $name) = each(%{$fails{pass}}) ) {
            $message  = "$message$host - $name<br>\n";
        }
    }

    if ( scalar( keys %{$fails{addr}} ) > 0 ) {
        $message  = "$message<br>\n<b>Железки без адреса на управление:</b><br>\n";
        while ( my ($host, $name) = each(%{$fails{addr}}) ) {
            $message  = "$message$host - $name<br>\n";
        }
    }

    if ( scalar( keys %{$fails{master}} ) > 0 ) {
        $message  = "$message<br>\n<b>Железки c MINT -type Master у которых в соседях есть Master:</b><br>\n";
        while ( my ($host, $name) = each(%{$fails{master}}) ) {
            $message  = "$message$host - $name<br>\n";
        }
    }

    if ( scalar( keys %{$fails{retries}} ) > 0 ) {
        $message  = "$message<br>\n<b>Железки c переповторами > 0.4:</b><br>\n";
        for (keys(%{$fails{retries}}) ) {
            $message  = "$message$_ - $fails{retries}{$_}{name} ($fails{retries}{$_}{client} - $fails{retries}{$_}{retries})<br>\n";
        }
    }

    if ( scalar( keys %{$fails{link}} ) > 0 ) {
        $message  = "$message<br>\n<b>Железки с линком в half-duplex на eth0:</b><br>\n";
            while ( my ($host, $name) = each(%{$fails{link}}) ) {
            $message  = "$message$host - $name<br>\n";
        }
    }

    $message  = "$message<br>\n<b>Мотивирующая картинка</b> - <a href=\"http://lurkmore.so/images/1/17/Byd_myzhikom_clean.jpeg\">http://lurkmore.so/images/1/17/Byd_myzhikom_clean.jpeg</a><br>\n";

    # получение текущего времени
    my($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime(time);

    # текущий месяц и год
    $mon = sprintf("%02d", ++$mon);
    $mday = sprintf("%02d", $mday);
    $year += 1900;

    mail_alert (\@alert_emails, $mail_from, "Epic Fail Compilation $year-$mon-$mday", $message);

    return;
}
