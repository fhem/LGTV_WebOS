###############################################################################
# 
# Developed with Kate
#
#  (c) 2017 Copyright: Marko Oldenburg (leongaultier at gmail dot com)
#  All rights reserved
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the textfile GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#
# $Id$
#
###############################################################################

#################################
######### Wichtige Hinweise und Links #################


##
#


################################


package main;

use strict;
use warnings;

use MIME::Base64;
use IO::Socket::INET;
use Digest::SHA qw(sha1_hex);
use JSON qw(decode_json encode_json);





my $version = "0.0.30";





# Declare functions
sub LGTV_WebOS_Initialize($);
sub LGTV_WebOS_Define($$);
sub LGTV_WebOS_Undef($$);
sub LGTV_WebOS_Set($@);
sub LGTV_WebOS_Open($);
sub LGTV_WebOS_Close($);
sub LGTV_WebOS_Read($);
sub LGTV_WebOS_Write($@);
sub LGTV_WebOS_Attr(@);
sub LGTV_WebOS_Handshake($);
sub LGTV_WebOS_ResponseProcessing($$);
sub LGTV_WebOS_Header2Hash($);
sub LGTV_WebOS_Pairing($);
sub LGTV_WebOS_CreateSendCommand($$$;$);
sub LGTV_WebOS_Hybi10Encode($;$$);
sub LGTV_WebOS_PreResponseProsessing($$);
sub LGTV_WebOS_WriteReadings($$);
sub LGTV_WebOS_GetCurrentChannel($);
sub LGTV_WebOS_GetForgroundAppInfo($);
sub LGTV_WebOS_GetAudioStatus($);
sub LGTV_WebOS_TimerStatusRequest($);




my %lgCommands = (

            "getServiceList"            => ["ssap://api/getServiceList"],
            "getChannelList"            => ["ssap://tv/getChannelList"],
            "getVolume"                 => ["ssap://audio/getVolume"],
            "getAudioStatus"            => ["ssap://audio/getStatus"],
            "getCurrentChannel"         => ["ssap://tv/getCurrentChannel"],
            "getChannelProgramInfo"     => ["ssap://tv/getChannelProgramInfo"],
            "getForegroundAppInfo"      => ["ssap://com.webos.applicationManager/getForegroundAppInfo"],
            "getAppList"                => ["ssap://com.webos.applicationManager/listApps"],
            "screenMsg"                 => ["ssap://system.notifications/createToast", "message"],
            "mute"                      => ["ssap://audio/setMute", "mute"],
            "powerOff"                  => ["ssap://system/turnOff"],
            "powerOn"                   => ["ssap://system/turnOn"],
            "volume"                    => ["ssap://audio/setVolume", "volume"],
            "volumeUp"                  => ["ssap://audio/volumeUp"],
            "volumeDown"                => ["ssap://audio/volumeDown"],
            "channelDown"               => ["ssap://tv/channelDown"],
            "channelUp"                 => ["ssap://tv/channelUp"],
            "openChannel"               => ["ssap://tv/openChannel", "channel"],
);





sub LGTV_WebOS_Initialize($) {

    my ($hash) = @_;
    
    # Provider
    $hash->{ReadFn}     = "LGTV_WebOS_Read";
    $hash->{WriteFn}    = "LGTV_WebOS_Write";


    # Consumer
    $hash->{SetFn}      = "LGTV_WebOS_Set";
    $hash->{DefFn}      = "LGTV_WebOS_Define";
    $hash->{UndefFn}    = "LGTV_WebOS_Undef";
    $hash->{AttrFn}     = "LGTV_WebOS_Attr";
    $hash->{AttrList}   = "disable:1 ".
                          $readingFnAttributes;


    foreach my $d(sort keys %{$modules{LGTV_WebOS}{defptr}}) {
        my $hash = $modules{LGTV_WebOS}{defptr}{$d};
        $hash->{VERSION} 	= $version;
    }
}

sub LGTV_WebOS_Define($$) {

    my ( $hash, $def ) = @_;
    
    my @a = split( "[ \t][ \t]*", $def );
    

    return "too few parameters: define <name> LGTV_WebOS <HOST>" if( @a != 3 );
    


    my $name            = $a[0];
    my $host            = $a[2];

    $hash->{HOST}       = $host;
    $hash->{VERSION}    = $version;


    Log3 $name, 3, "LGTV_WebOS ($name) - defined with host $host";

    $attr{$name}{devStateIcon} = 'on:10px-kreis-gruen:off off:10px-kreis-rot:on' if( !defined( $attr{$name}{devStateIcon} ) );
    $attr{$name}{room} = 'LGTV' if( !defined( $attr{$name}{room} ) );
    
    readingsSingleUpdate($hash,'state','off', 1);
    
    
    $modules{LGTV_WebOS}{defptr}{$hash->{HOST}} = $hash;
    
    
    if( $init_done ) {
        LGTV_WebOS_Open($hash);
    } else {
        InternalTimer( gettimeofday()+15, "LGTV_WebOS_Open", $hash, 0 );
    }
    
    return undef;
}

sub LGTV_WebOS_Undef($$) {

    my ( $hash, $arg ) = @_;
    
    my $host = $hash->{HOST};
    my $name = $hash->{NAME};
    
    
    RemoveInternalTimer($hash);
    
    LGTV_WebOS_Close($hash);
    delete $modules{LGTV_WebOS}{defptr}{$hash->{HOST}};
    
    Log3 $name, 3, "LGTV_WebOS ($name) - device $name deleted";
    
    return undef;
}

sub LGTV_WebOS_Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};
    
    my $orig = $attrVal;

    
    if( $attrName eq "disable" ) {
        if( $cmd eq "set" and $attrVal eq "1" ) {
            readingsSingleUpdate ( $hash, "state", "disabled", 1 );
            Log3 $name, 3, "LGTV_WebOS ($name) - disabled";
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "LGTV_WebOS ($name) - enabled";
        }
    }
    
    if( $attrName eq "disabledForIntervals" ) {
        if( $cmd eq "set" ) {
            Log3 $name, 3, "LGTV_WebOS ($name) - enable disabledForIntervals";
            readingsSingleUpdate ( $hash, "state", "Unknown", 1 );
        }

        elsif( $cmd eq "del" ) {
            readingsSingleUpdate ( $hash, "state", "active", 1 );
            Log3 $name, 3, "LGTV_WebOS ($name) - delete disabledForIntervals";
        }
    }

    return undef;
}

sub LGTV_WebOS_TimerStatusRequest($) {

    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    
    RemoveInternalTimer($hash,'LGTV_WebOS_TimerStatusRequest');
    
    if( !IsDisabled($name) and $hash->{CD} ) {
    
        Log3 $name, 4, "LGTV_WebOS ($name) - run get functions";
    
        InternalTimer( gettimeofday()+1, 'LGTV_WebOS_GetAudioStatus', $hash, 0 );
        InternalTimer( gettimeofday()+2, 'LGTV_WebOS_GetCurrentChannel', $hash, 0 );
        InternalTimer( gettimeofday()+3, 'LGTV_WebOS_GetForgroundAppInfo', $hash, 0 );
        
    } elsif( IsDisabled($name) ) {
        readingsSingleUpdate ( $hash, "state", "disabled", 1 );
    }
    
    
    LGTV_WebOS_Open($hash) if( !IsDisabled($name) and not $hash->{CD} );
    
    InternalTimer( gettimeofday()+10,"LGTV_WebOS_TimerStatusRequest", $hash, 1 );
}

sub LGTV_WebOS_Set($@) {

    my ($hash, $name, $cmd, @args) = @_;
    my ($arg, @params)  = @args;

    my $uri;
    my %payload;
    
    
    if($cmd eq 'connect') {
        return "usage: connect" if( @args != 0 );

        LGTV_WebOS_Open($hash);

        return undef;

    } elsif($cmd eq 'pairing') {
        return "usage: pairing" if( @args != 0 );

        LGTV_WebOS_Pairing($hash);

        return undef;
        
    } elsif($cmd eq 'screenMsg') {
        return "usage: screenMsg <message>" if( @args < 1 );

        $payload{$lgCommands{$cmd}->[1]}    = join(" ", @args);
        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'on' or $cmd eq 'off') {
        return "usage: on/off" if( @args != 0 );

        if($cmd eq 'off') {
            $uri                                = $lgCommands{powerOff};
        } elsif ($cmd eq 'on') {
            $uri                                = $lgCommands{powerOn};
        }
        
    } elsif($cmd eq 'mute') {
        return "usage: mute" if( @args != 1 );

        if($args[0] eq 'off') {
        
            $payload{$lgCommands{$cmd}->[1]}    = 'false';
        
        } elsif($args[0] eq 'on') {
        
            $payload{$lgCommands{$cmd}->[1]}    = 'true';
        }
        
        $uri                                = $lgCommands{$cmd}->[0];

    } elsif($cmd eq 'volume') {
        return "usage: volume" if( @args != 1 );

        $payload{$lgCommands{$cmd}->[1]}    = join(" ", @args);
        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'volumeUp') {
        return "usage: volumeUp" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'volumeDown') {
        return "usage: volumeDown" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'channelDown') {
        return "usage: channelDown" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'channelUp') {
        return "usage: channelUp" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'openChannel') {
        return "usage: openChannel" if( @args != 1 );

        $payload{$lgCommands{$cmd}->[1]}    = join(" ", @args);
        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'getServiceList') {
        return "usage: getServiceList" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'getChannelProgramInfo') {
        return "usage: getChannelProgramInfo" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'getChannelList') {
        return "usage: getChannelList" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];
        
    } elsif($cmd eq 'getAppList') {
        return "usage: getAppList" if( @args != 0 );

        $uri                                = $lgCommands{$cmd}->[0];

    } else {
        my  $list = ""; 
        $list .= "connect:noArg pairing:noArg screenMsg mute:on,off volume volumeUp:noArg volumeDown:noArg channelDown:noArg channelUp:noArg openChannel getServiceList:noArg on:noArg off:noArg getAppList:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }
    
    LGTV_WebOS_CreateSendCommand($hash,$uri,\%payload);
}

sub LGTV_WebOS_Open($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    my $host    = $hash->{HOST};
    my $port    = 3000;
    my $timeout = 1;
    
    
    Log3 $name, 4, "LGTV_WebOS ($name) - Baue Socket Verbindung auf";
    

    my $socket = new IO::Socket::INET   (   PeerHost => $host,
                                            PeerPort => $port,
                                            Proto => 'tcp',
                                            Timeout => 0.1
                                        )
        or return Log3 $name, 4, "LGTV_WebOS ($name) Couldn't connect to $host:$port";      # open Socket
        
    $hash->{FD}    = $socket->fileno();
    $hash->{CD}    = $socket;         # sysread / close won't work on fileno
    $selectlist{$name} = $hash;
    
    
    Log3 $name, 4, "LGTV_WebOS ($name) - Socket Connected";
    
    LGTV_WebOS_Handshake($hash);
    Log3 $name, 4, "LGTV_WebOS ($name) - start Handshake";
    
}

sub LGTV_WebOS_Close($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    return if( !$hash->{CD} );

    close($hash->{CD}) if($hash->{CD});
    delete($hash->{FD});
    delete($hash->{CD});
    delete($selectlist{$name});
    
    readingsSingleUpdate($hash, 'state', 'off', 1 );
    
    Log3 $name, 4, "LGTV_WebOS ($name) - Socket Disconnected";
}

sub LGTV_WebOS_Write($@) {

    my ($hash,$string)  = @_;
    my $name            = $hash->{NAME};
    
    
    Log3 $name, 4, "LGTV_WebOS ($name) - WriteFn called";
    
    return Log3 $name, 4, "LGTV_WebOS ($name) - socket not connected"
    unless($hash->{CD});

    Log3 $name, 5, "LGTV_WebOS ($name) - $string";
    syswrite($hash->{CD}, $string);
    return undef;
}

sub LGTV_WebOS_Read($) {

    my $hash = shift;
    my $name = $hash->{NAME};
    
    my $len;
    my $buf;
    
    Log3 $name, 4, "LGTV_WebOS ($name) - ReadFn gestartet";

    $len = sysread($hash->{CD},$buf,1024);          # die genaue Puffergröße wird noch ermittelt
    
    if( !defined($len) or !$len ) {
        Log3 $name, 5, "LGTV_WebOS ($name) - connection closed by remote Host";
        LGTV_WebOS_Close($hash);
        return;
    }
    
	unless( defined $buf) { 
        Log3 $name, 3, "LGTV_WebOS ($name) - Keine Daten empfangen";
        return; 
    }
    
    Log3 $name, 5, "LGTV_WebOS ($name) - received buffer data, start response processing: $buf";
    LGTV_WebOS_ResponseProcessing($hash,$buf);
}

sub LGTV_WebOS_Handshake($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    my $host    = $hash->{HOST};
    my $wsKey   = encode_base64(gettimeofday());
    
    my $wsHandshakeCmd  = "";
    $wsHandshakeCmd     .= "GET / HTTP/1.1\r\n";
    $wsHandshakeCmd     .= "Host: $host\r\n";
    $wsHandshakeCmd     .= "User-Agent: FHEM\r\n";
    $wsHandshakeCmd     .= "Upgrade: websocket\r\n";
    $wsHandshakeCmd     .= "Connection: Upgrade\r\n";
    $wsHandshakeCmd     .= "Sec-WebSocket-Version: 13\r\n";            
    $wsHandshakeCmd     .= "Sec-WebSocket-Key: " . $wsKey . "\r\n";
    
    LGTV_WebOS_Write($hash,$wsHandshakeCmd);
    
    $hash->{helper}{wsKey}  = $wsKey;
    
    Log3 $name, 5, "LGTV_WebOS ($name) - send Handshake to WriteFn";
    
    
    LGTV_WebOS_TimerStatusRequest($hash);
    Log3 $name, 4, "LGTV_WebOS ($name) - start timer status request";
    
    LGTV_WebOS_Pairing($hash);
    Log3 $name, 4, "LGTV_WebOS ($name) - start pairing routine";
}

sub LGTV_WebOS_ResponseProcessing($$) {

    my ($hash,$response)    = @_;
    my $name            = $hash->{NAME};
    
    
    
    
    ########################
    ### Response has HTML Header
    if( $response =~ /HTTP\/1.1 101 Switching Protocols/ ) {
    
        my $data        = $response;
        my $header      = LGTV_WebOS_Header2Hash($data);
        
        ################################
        ### Handshake for first Connect
        if( defined($header->{'Sec-WebSocket-Accept'})) {
    
            my $keyAccept   = $header->{'Sec-WebSocket-Accept'};
            Log3 $name, 5, "LGTV_WebOS ($name) - keyAccept: $keyAccept";
        
            my $wsKey   = $hash->{helper}{wsKey};
            my $expectedResponse = trim(encode_base64(pack('H*', sha1_hex(trim($wsKey)."258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))));
        
            if ($keyAccept eq $expectedResponse) {
        
                Log3 $name, 3, "LGTV_WebOS ($name) - Sucessfull WS connection to $hash->{HOST}";
                readingsSingleUpdate($hash, 'state', 'on', 1 );
        
            } else {
                LGTV_WebOS_Close($hash);
                Log3 $name, 3, "LGTV_WebOS ($name) - ERROR: Unsucessfull WS connection to $hash->{HOST}";
            }
        }
        
        return undef;
    }
    
    
    elsif( $response =~ m/[\[{].*[}\]]$/ ) {
    
        Log3 $name, 4, "LGTV_WebOS ($name) - JSON detected, beginn PreResponseProsessing";
        
        my $json        = LGTV_WebOS_PreResponseProsessing($hash,$response);
        Log3 $name, 5, "LGTV_WebOS ($name) - Corrected JSON String: $json";
        
        my $decode_json     = decode_json($json);
        
        LGTV_WebOS_WriteReadings($hash,$decode_json);
        
        return undef;
    }
    
    
    Log3 $name, 4, "LGTV_WebOS ($name) - no Match found";
}

sub LGTV_WebOS_WriteReadings($$) {

    my ($hash,$decode_json)    = @_;
    
    my $name            = $hash->{NAME};
    my $mute;
    my $response;

    
    Log3 $name, 4, "LGTV_WebOS ($name) - Beginn Readings writing";
    
    
    

    readingsBeginUpdate($hash);
    
    if( ref($decode_json->{payload}{services}) eq "ARRAY" and scalar(@{$decode_json->{payload}{services}}) > 0 ) {
        foreach my $services (@{$decode_json->{payload}{services}}) {
        
            readingsBulkUpdate($hash,'service_'.$services->{name},'v.'.$services->{version});
        }
    }
    
    if( defined($decode_json->{payload}{'mute'}) or defined($decode_json->{payload}{'muted'})) {
        if( defined($decode_json->{payload}{'mute'}) and $decode_json->{payload}{'mute'} eq 'true' ) {
    
            readingsBulkUpdate($hash,'mute','on');
            
        } elsif( defined($decode_json->{payload}{'mute'}) and $decode_json->{payload}{'mute'} eq 'false' ) {
        
            readingsBulkUpdate($hash,'mute','off');
        
        } 
        
        if( defined($decode_json->{payload}{'muted'}) and $decode_json->{payload}{'muted'} eq 'true' ) {
        
                readingsBulkUpdate($hash,'mute','on');
            
        } elsif( defined($decode_json->{payload}{'muted'}) and $decode_json->{payload}{'muted'} eq 'false' ) {
        
            readingsBulkUpdate($hash,'mute','off');
        }
    }
    
    if( defined($decode_json->{type}) ) {
        if( ($decode_json->{type} eq 'response' and $decode_json->{payload}{returnValue} eq 'true') or ($decode_json->{type} eq 'registered') and defined($decode_json->{payload}{'client-key'}) ) {
        
            $response = 'ok';   # if( $decode_json->{type} eq 'response' and $decode_json->{payload}{returnValue} eq 'true' );
            readingsBulkUpdate($hash,'pairing','paired');
            
        } elsif( $decode_json->{type} eq 'error' ) {
        
            $response = "error - $decode_json->{error}";
            
            if($decode_json->{error} eq '401 insufficient permissions' or $decode_json->{error} eq '401 insufficient permissions (not registered)') {
            
                readingsBulkUpdate($hash,'pairing','unpaired');
            }
        }
    }
    
    
    readingsBulkUpdate($hash,'lgKey',$decode_json->{payload}{'client-key'});
    readingsBulkUpdate($hash,'volume',$decode_json->{payload}{'volume'});
    readingsBulkUpdate($hash,'lastResponse',$response);
    
    readingsBulkUpdate($hash,'currentChannelNumber',$decode_json->{payload}{'channelNumber'});
    readingsBulkUpdate($hash,'currentChannelName',$decode_json->{payload}{'channelName'});
    readingsBulkUpdate($hash,'currentChannelTypeName',$decode_json->{payload}{'channelTypeName'});
    readingsBulkUpdate($hash,'currentApp',$decode_json->{payload}{'appId'});
    
    readingsEndUpdate($hash, 1);
}

sub LGTV_WebOS_Pairing($) {

    my $hash    = shift;
    my $name    = $hash->{NAME};
    
    my $lgKey;
    
    Log3 $name, 4, "LGTV_WebOS ($name) - HASH handshakePayload";
    
    my %handshakePayload =  (   "pairingType" => "PROMPT",
                                "manifest" => {
                                    "manifestVersion" => 1,
                                    "appVersion" => "1.1",
                                    "signed" => {
                                        "created" => "20161123",
                                        "appId" => "com.lge.test",
                                        "vendorId" => "com.lge",
                                        "localizedAppNames" => {
                                            "" => "FHEM LG Remote",
                                            "de-DE" => "FHEM LG Fernbedinung"
                                            },
                                        "localizedVendorNames" => {
                                            "" => "LG Electronics"
                                        },
                                        "permissions" => [
                                            "TEST_SECURE",
                                            "CONTROL_INPUT_TEXT",
                                            "CONTROL_MOUSE_AND_KEYBOARD",
                                            "READ_INSTALLED_APPS",
                                            "READ_LGE_SDX",
                                            "READ_NOTIFICATIONS",
                                            "SEARCH",
                                            "WRITE_SETTINGS",
                                            "WRITE_NOTIFICATION_ALERT",
                                            "CONTROL_POWER",
                                            "READ_CURRENT_CHANNEL",
                                            "READ_RUNNING_APPS",
                                            "READ_UPDATE_INFO",
                                            "UPDATE_FROM_REMOTE_APP",
                                            "READ_LGE_TV_INPUT_EVENTS",
                                            "READ_TV_CURRENT_TIME"
                                        ],
                                        "serial" => "2f930e2d2cfe083771f68e4fe7bb07"
                                    },
                                    "permissions" => [
                                        "LAUNCH",
                                        "LAUNCH_WEBAPP",
                                        "APP_TO_APP",
                                        "CLOSE",
                                        "TEST_OPEN",
                                        "TEST_PROTECTED",
                                        "CONTROL_AUDIO",
                                        "CONTROL_DISPLAY",
                                        "CONTROL_INPUT_JOYSTICK",
                                        "CONTROL_INPUT_MEDIA_RECORDING",
                                        "CONTROL_INPUT_MEDIA_PLAYBACK",
                                        "CONTROL_INPUT_TV",
                                        "CONTROL_POWER",
                                        "READ_APP_STATUS",
                                        "READ_CURRENT_CHANNEL",
                                        "READ_INPUT_DEVICE_LIST",
                                        "READ_NETWORK_STATE",
                                        "READ_RUNNING_APPS",
                                        "READ_TV_CHANNEL_LIST",
                                        "WRITE_NOTIFICATION_TOAST",
                                        "READ_POWER_STATE",
                                        "READ_COUNTRY_INFO"
                                    ],
                                    "signatures" => [
                                        {
                                            "signatureVersion" => 1,
                                            "signature" => "eyJhbGdvcml0aG0iOiJSU0EtU0hBMjU2Iiwia2V5SWQiOiJ0ZXN0LXNpZ25pbmctY2VydCIsInNpZ25hdHVyZVZlcnNpb24iOjF9.hrVRgjCwXVvE2OOSpDZ58hR+59aFNwYDyjQgKk3auukd7pcegmE2CzPCa0bJ0ZsRAcKkCTJrWo5iDzNhMBWRyaMOv5zWSrthlf7G128qvIlpMT0YNY+n/FaOHE73uLrS/g7swl3/qH/BGFG2Hu4RlL48eb3lLKqTt2xKHdCs6Cd4RMfJPYnzgvI4BNrFUKsjkcu+WD4OO2A27Pq1n50cMchmcaXadJhGrOqH5YmHdOCj5NSHzJYrsW0HPlpuAx/ECMeIZYDh6RMqaFM2DXzdKX9NmmyqzJ3o/0lkk/N97gfVRLW5hA29yeAwaCViZNCP8iC9aO0q9fQojoa7NQnAtw=="
                                        }
                                    ]
                                }
                            );


    my $usedHandshake = \%handshakePayload;
    
    my $key = ReadingsVal($name, 'lgKey', '');

    $usedHandshake->{'client-key'} = $key if( defined($key));
    
    LGTV_WebOS_CreateSendCommand($hash, undef, $usedHandshake, 'register');
    Log3 $name, 4, "LGTV_WebOS ($name) - Send pairing informations";
}

sub LGTV_WebOS_CreateSendCommand($$$;$) {

    my ($hash, $uri, $payload, $type)   = @_;
    
    my $name                            = $hash->{NAME};
    my $err;
    
    
    $type = 'request' if( not defined($type) );
    
    my $command = {};
    $command->{'client-key'} = ReadingsVal($name, 'lgKey', '') if( $type ne 'register' );
    $command->{id} = $type."_".gettimeofday();
    $command->{type} = $type;
    $command->{uri} = $uri if($uri);
    $command->{payload} = $payload if( defined($payload) );
    
    #Log3 $name, 5, "LGTV_WebOS ($name) - Payload Message: $command->{payload}{message}";
    
    my $cmd = encode_json($command);
    
    Log3 $name, 5, "LGTV_WebOS ($name) - Sending command: $cmd";
    
    LGTV_WebOS_Write($hash, LGTV_WebOS_Hybi10Encode($cmd, "text", 1));
    
    return undef;
}

sub LGTV_WebOS_Hybi10Encode($;$$) {

    my ($payload, $type, $masked) = @_;
    
    
    $type //= "text";
    $masked //= 1;

    my @frameHead;
    my $frame = "";
    my $payloadLength = length($payload);

    
    if ($type eq "text") {
    
        # first byte indicates FIN, Text-Frame (10000001):
        $frameHead[0] = 129;
        
    } elsif ($type eq "close") {
    
        # first byte indicates FIN, Close Frame(10001000):
        $frameHead[0] = 136;
        
    } elsif ($type eq "ping") {
    
        # first byte indicates FIN, Ping frame (10001001):
        $frameHead[0] = 137;
    
    } elsif ($type eq "pong") {
    
        # first byte indicates FIN, Pong frame (10001010):
        $frameHead[0] = 138;
    }

    # set mask and payload length (using 1, 3 or 9 bytes)
    if ($payloadLength > 65535) {
    
        # TODO
        my $payloadLengthBin = sprintf('%064b', $payloadLength);
        $frameHead[1] = ($masked) ? 255 : 127;
    
        for (my $i = 0; $i < 8; $i++) {
        
            $frameHead[$i + 2] = oct("0b".substr($payloadLengthBin, $i*8, $i*8+8));
        }

        # most significant bit MUST be 0 (close connection if frame too big)
        if ($frameHead[2] > 127) {
        
            #$this->close(1004);
            return undef;
        }
        
    } elsif ($payloadLength > 125) {
    
        my $payloadLengthBin = sprintf('%016b', $payloadLength);
        $frameHead[1] = ($masked) ? 254 : 126;
        $frameHead[2] = oct("0b".substr($payloadLengthBin, 0, 8));
        $frameHead[3] = oct("0b".substr($payloadLengthBin, 8, 16));
        
    } else {
    
        $frameHead[1] = ($masked) ? $payloadLength + 128 : $payloadLength;
    }

    # convert frame-head to string:
    for (my $i = 0; $i < scalar(@frameHead); $i++) {
    
        $frameHead[$i] = chr($frameHead[$i]);
    }
    
    my @mask;
    if ($masked) {
        # generate a random mask:
        for (my $i = 0; $i < 4; $i++) {
        
            #$mask[$i] = chr(int(rand(255)));
            $mask[$i] = chr(int(25*$i));
        }
        
        @frameHead = (@frameHead, @mask);
    }
    
    $frame = join("", @frameHead);

    # append payload to frame:
    my $char;
    for (my $i = 0; $i < $payloadLength; $i++) {
    
        $char = substr($payload, $i, 1);
        $frame .= ($masked) ? $char ^ $mask[$i % 4] : $char;
    }
    
    return $frame;
}

sub LGTV_WebOS_GetAudioStatus($) {

    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    
    RemoveInternalTimer($hash,'LGTV_WebOS_GetAudioStatus');
    LGTV_WebOS_CreateSendCommand($hash,$lgCommands{getAudioStatus},undef);
}

sub LGTV_WebOS_GetCurrentChannel($) {

    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    
    RemoveInternalTimer($hash,'LGTV_WebOS_GetCurrentChannel');
    LGTV_WebOS_CreateSendCommand($hash,$lgCommands{getCurrentChannel},undef);
}

sub LGTV_WebOS_GetForgroundAppInfo($) {

    my $hash        = shift;
    my $name        = $hash->{NAME};
    
    
    RemoveInternalTimer($hash,'LGTV_WebOS_GetForgroundAppInfo');
    LGTV_WebOS_CreateSendCommand($hash,$lgCommands{getForegroundAppInfo},undef);
}




#############################################
### my little Helper

sub LGTV_WebOS_Header2Hash($) {

    my ( $string ) = @_;
    my %hash = ();

    foreach my $line (split("\r\n", $string)) {
        my ($key,$value) = split( ": ", $line );
        next if( !$value );

        $value =~ s/^ //;
        $hash{$key} = $value;
    }     
        
    return \%hash;
}

sub LGTV_WebOS_PreResponseProsessing($$) {

    my ($hash,$json)    = @_;
    my $name            = $hash->{NAME};
    
    
    Log3 $name, 4, "LGTV_WebOS ($name) - pre processing response data";
    
    my $len = length($json);
    my @letterArray = split("",$json);

    my $letter  = "";
    my $count   = 0;
    my $marker  = 0;
    my $corrected_json;

    for(my $i = 0; $i < $len; $i++) {

        $marker     = 1 if($count > 0);
        $letter         = $letterArray[0];
        
        $count++ if($letter eq '{');
        $count-- if($letter eq '}');
        
        $corrected_json .= $letter if($count > 0);


        if( $count == 0 and $marker == 1 ) {
     
            $marker = 0;
            $corrected_json .= '}';
            return $corrected_json;
        }

        shift(@letterArray);
    }
}












1;
