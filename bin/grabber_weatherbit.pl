#!/usr/bin/perl

# grabber for fetching data from Weatherbit.io
# fetches weather data (current and forecast) from Weatherbit.io

# Copyright 2016-2018 Michael Schlenstedt, michael@loxberry.de
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

##########################################################################
# Modules
##########################################################################

use LoxBerry::System;
use LoxBerry::Log;
use LWP::UserAgent;
use JSON qw( decode_json );
use File::Copy;
use Getopt::Long;
use Time::Piece;

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

my $pcfg           = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $url            = $pcfg->param("WEATHERBIT.URL");
my $apikey         = $pcfg->param("WEATHERBIT.APIKEY");
my $lang           = $pcfg->param("WEATHERBIT.LANG");
my $stationid      = "lat=" . $pcfg->param("WEATHERBIT.COORDLAT") . "&lon=" . $pcfg->param("WEATHERBIT.COORDLONG");
my $city           = $pcfg->param("WEATHERBIT.STATION");
my $country        = $pcfg->param("WEATHERBIT.COUNTRY");
my $fillmissinghfc = $pcfg->param("WEATHERBIT.FILLMISSINGDATA");

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'grabber_weatherbit',
	logdir => "$lbplogdir",
	#filename => "$lbplogdir/weather4lox.log",
	#append => 1,
);

# Commandline options
my $verbose = '';
my $current = '';
my $daily = '';
my $hourly = '';

GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 },
            'current' => \$current,
            'daily' => \$daily,
            'hourly' => \$hourly);

# Due to a bug in the Logging routine, set the loglevel fix to 3
#$log->loglevel(3);
if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

LOGSTART "Weather4Lox GRABBER_WEATHERBIT process started";
LOGDEB "This is $0 Version $version";

my $t;
my $weather;
my $code;
my $icon;
my $wdir;
my $wdirdes;
my @filecontent;
my $i;
my $error;
my $moonpercent;

if ($current) { # Start Current

# Get data from Weatherbit Server (API request) for current conditions
my $queryurlcr = "$url/current?key=$apikey&$stationid&lang=$lang&units=M&marine=f";

$error = 0;
LOGINF "Fetching Current Data for Location $stationid";
LOGDEB "URL: $queryurlcr";

my $ua = new LWP::UserAgent;
my $res = $ua->get($queryurlcr);
my $json = $res->decoded_content();

# Check status of request
my $urlstatus = $res->status_line;
my $urlstatuscode = substr($urlstatus,0,3);

LOGDEB "Status: $urlstatus";

if ($urlstatuscode ne "200") {
  LOGCRIT "Failed to fetch data for $stationid\. Status Code: $urlstatuscode";
  exit 2;
} else {
  LOGOK "Data fetched successfully for $stationid";
}

# Decode JSON response from server
my $decoded_json = decode_json( "$json" );

# Write location data into database
my $t = localtime($decoded_json->{data}->[0]->{ts});
LOGINF "Saving new Data for Timestamp $t to database.";

# Saving new current data...
my $error = 0;
open(F,">$lbplogdir/current.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbpconfigdir/current.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	print F "$decoded_json->{data}->[0]->{ts}|";
	my $date = qx(date -R -d "\@$decoded_json->{data}->[0]->{ts}");
	chomp ($date);
	print F "$date|";
	my $tz_short = qx(TZ='$decoded_json->{data}->[0]->{timezone}' date +%Z);
	chomp ($tz_short);
	print F "$tz_short|";
	print F "$decoded_json->{data}->[0]->{timezone}|";
	my $tz_offset = qx(TZ="$decoded_json->{data}->[0]->{timezone}" date +%z);
	chomp ($tz_offset);
	print F "$tz_offset|";
	print F "$decoded_json->{data}->[0]->{city_name}|";
	$country = Encode::decode("UTF-8", $country);
	print F "$country|";
	print F "$decoded_json->{data}->[0]->{country_code}|";
	print F "$decoded_json->{data}->[0]->{lat}|";
	print F "$decoded_json->{data}->[0]->{lon}|";
	print F "-9999|";
	print F sprintf("%.1f",$decoded_json->{data}->[0]->{temp}), "|";
	print F sprintf("%.1f",$decoded_json->{data}->[0]->{app_temp}), "|";
	print F "$decoded_json->{data}->[0]->{rh}|";
	$wdir = $decoded_json->{data}->[0]->{wind_dir};
	if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
	if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
	if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
	if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
	if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
	if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
	if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
	if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
	if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
	print F "$wdirdes|";
	print F "$decoded_json->{data}->[0]->{wind_dir}|";
	print F sprintf("%.1f",$decoded_json->{data}->[0]->{wind_spd} * 3.6), "|";
	print F sprintf("%.1f",$decoded_json->{data}->[0]->{wind_spd} * 3.6), "|";
	print F sprintf("%.1f",$decoded_json->{data}->[0]->{app_temp}), "|";
	print F sprintf("%.0f",$decoded_json->{data}->[0]->{pres}), "|";
	print F "$decoded_json->{data}->[0]->{dewpt}|";
	print F "$decoded_json->{data}->[0]->{vis}|";
	print F "$decoded_json->{data}->[0]->{solar_rad}|";
	print F "-9999|";
	print F sprintf("%.1f",$decoded_json->{data}->[0]->{uv}),"|";
	print F "-9999|";
	print F sprintf("%.3f",$decoded_json->{data}->[0]->{precip}), "|";
	# Convert Weather string into Weather Code and convert icon name
  # Weather conditions: https://openweathermap.org/weather-conditions
	$weather = $decoded_json->{data}->[0]->{weather}->{code};
	$code = "";
	$icon = "";
	if ($weather eq "200") { $code = "18"; $icon = "tstorms" };
	if ($weather eq "201") { $code = "18"; $icon = "tstorms" };
	if ($weather eq "202") { $code = "19"; $icon = "tstorms" };
	if ($weather eq "210") { $code = "18"; $icon = "tstorms" };
	if ($weather eq "211") { $code = "18"; $icon = "tstorms" };
	if ($weather eq "212") { $code = "19"; $icon = "tstorms" };
	if ($weather eq "221") { $code = "19"; $icon = "tstorms" };
	if ($weather eq "230") { $code = "18"; $icon = "tstorms" };
	if ($weather eq "231") { $code = "18"; $icon = "tstorms" };
	if ($weather eq "232") { $code = "19"; $icon = "tstorms" };
	if ($weather eq "300") { $code = "13"; $icon = "chancerain" };
	if ($weather eq "301") { $code = "13"; $icon = "chancerain" };
	if ($weather eq "302") { $code = "13"; $icon = "chancerain" };
	if ($weather eq "310") { $code = "10"; $icon = "chancerain" };
	if ($weather eq "311") { $code = "11"; $icon = "rain" };
	if ($weather eq "312") { $code = "12"; $icon = "rain" };
	if ($weather eq "313") { $code = "12"; $icon = "rain" };
	if ($weather eq "314") { $code = "12"; $icon = "rain" };
	if ($weather eq "321") { $code = "12"; $icon = "rain" };
	if ($weather eq "500") { $code = "10"; $icon = "chancerain" };
	if ($weather eq "501") { $code = "11"; $icon = "rain" };
	if ($weather eq "502") { $code = "12"; $icon = "rain" };
	if ($weather eq "503") { $code = "12"; $icon = "rain" };
	if ($weather eq "504") { $code = "12"; $icon = "rain" };
	if ($weather eq "511") { $code = "14"; $icon = "sleet" };
	if ($weather eq "520") { $code = "10"; $icon = "rain" };
	if ($weather eq "521") { $code = "11"; $icon = "rain" };
	if ($weather eq "522") { $code = "12"; $icon = "rain" };
	if ($weather eq "531") { $code = "12"; $icon = "rain" };
	if ($weather eq "600") { $code = "20"; $icon = "snow" };
	if ($weather eq "601") { $code = "21"; $icon = "snow" };
	if ($weather eq "602") { $code = "22"; $icon = "snow" };
	if ($weather eq "611") { $code = "26"; $icon = "sleet" };
	if ($weather eq "612") { $code = "28"; $icon = "sleet" };
	if ($weather eq "613") { $code = "29"; $icon = "sleet" };
	if ($weather eq "615") { $code = "23"; $icon = "sleet" };
	if ($weather eq "616") { $code = "23"; $icon = "snow" };
	if ($weather eq "620") { $code = "21"; $icon = "snow" };
	if ($weather eq "621") { $code = "21"; $icon = "snow" };
	if ($weather eq "622") { $code = "21"; $icon = "snow" };
	if ($weather eq "701") { $code = "6";  $icon = "fog" };
	if ($weather eq "711") { $code = "6";  $icon = "fog" };
	if ($weather eq "721") { $code = "5";  $icon = "hazy" };
	if ($weather eq "731") { $code = "6";  $icon = "fog" };
	if ($weather eq "741") { $code = "6";  $icon = "fog" };
	if ($weather eq "751") { $code = "6";  $icon = "fog" };
	if ($weather eq "761") { $code = "6";  $icon = "fog" };
	if ($weather eq "762") { $code = "6";  $icon = "fog" };
	if ($weather eq "771") { $code = "19";  $icon = "tstorms" };
	if ($weather eq "781") { $code = "19";  $icon = "tstorms" };
	if ($weather eq "800") { $code = "1";  $icon = "clear" };
	if ($weather eq "801") { $code = "2";  $icon = "mostlysunny" };
	if ($weather eq "802") { $code = "3";  $icon = "mostlycloudy" };
	if ($weather eq "803") { $code = "4";  $icon = "cloudy" };
	if ($weather eq "804") { $code = "5";  $icon = "overcast" };
	if (!$icon) { $icon = "rain" };
  if (!$code) { $code = "13" };
	print F "$icon|";
	print F "$code|";
	print F "$decoded_json->{data}->[0]->{weather}->{description}|";
	print F "MOONPERCENT|";
	print F "-9999|";
	print F "-9999|";
	print F "-9999|";
	my ($srhour, $srmin) = split /:/, $decoded_json->{data}->[0]->{sunrise};
	# Sunrise/Sunset time is not in local time but UTC
	my $offset = qx(TZ="$decoded_json->{data}->[0]->{timezone}" date +%:::z);
	chomp ($offset);
	$srhour = qx(date --date "$decoded_json->{data}->[0]->{sunrise} +$offset hours" +%H);
	chomp ($srhour);
	print F "$srhour|";
	$srmin = qx(date --date "$decoded_json->{data}->[0]->{sunrise} +$offset hours" +%M);
	chomp ($srmin);
	print F "$srmin|";
	my $sshour = qx(date --date "$decoded_json->{data}->[0]->{sunset} +$offset hours" +%H);
	chomp ($sshour);
	print F "$sshour|";
	my $ssmin = qx(date --date "$decoded_json->{data}->[0]->{sunset} +$offset hours" +%M);
	chomp ($ssmin);
	print F "$ssmin|";
	print F "-9999|";
	print F "$decoded_json->{data}->[0]->{clouds}|";
	print F "-9999|";
	print F sprintf("%.3f",$decoded_json->{data}->[0]->{snow} / 10), "|";
	print F "\n";
  flock(F,8);
close(F);

LOGOK "Saving current data to $lbplogdir/current.dat.tmp successfully.";

my @filecontent;
LOGDEB "Database content:";
open(F,"<$lbplogdir/current.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
	# Convert elevation from feet to meter
		LOGDEB "$_";
	}
close (F);

} # End Current

if ($daily) { # Start Daily

# Saving new daily forecast data...

# Get data from Weatherbit Server (API request) for current conditions
my $queryurlcr = "$url/forecast/daily?key=$apikey&$stationid&lang=$lang&units=M&marine=f";

LOGINF "Fetching Daily Forecast Data for Location $stationid";
LOGDEB "URL: $queryurlcr";

my $ua = new LWP::UserAgent;
my $res = $ua->get($queryurlcr);
my $json = $res->decoded_content();

# Check status of request
my $urlstatus = $res->status_line;
my $urlstatuscode = substr($urlstatus,0,3);

LOGDEB "Status: $urlstatus";

if ($urlstatuscode ne "200") {
  LOGCRIT "Failed to fetch data for $stationid\. Status Code: $urlstatuscode";
  exit 2;
} else {
  LOGOK "Data fetched successfully for $stationid";
}

# Decode JSON response from server
my $decoded_json = decode_json( "$json" );

$error = 0;
open(F,">$lbplogdir/dailyforecast.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/dailyforecast.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	my $i = 1;
	for my $results( @{$decoded_json->{data}} ){
		print F "$i|";
		$i++;
		print F $results->{ts}, "|";
		$t = localtime($results->{ts});
		print F sprintf("%02d", $t->mday), "|";
		print F sprintf("%02d", $t->mon), "|";
		my @month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		@month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		print F $t->year . "|";
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		my @days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		@days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		print F sprintf("%.1f",$results->{max_temp}), "|";
		print F sprintf("%.1f",$results->{min_temp}), "|";
		print F "$results->{pop}|";
		print F sprintf("%.3f",$results->{precip}), "|";
		print F sprintf("%.3f",$results->{snow} / 10), "|";
		print F sprintf("%.1f",$results->{wind_gust_spd} * 3.6), "|";
		$wdir = $results->{wind_dir};
		if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
		if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
		if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
		if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
		if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
		if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
		if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
		if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		print F "$wdirdes|";
		print F "$results->{wind_dir}|";
		print F sprintf("%.1f",$results->{wind_spd} * 3.6), "|";
		print F "$wdirdes|";
		print F "$results->{wind_dir}|";
		print F "$results->{rh}|";
		print F "-9999|";
		print F "-9999|";
		# Convert Weather string into Weather Code and convert icon name
		$weather = $results->{weather}->{code};
  	$code = "";
  	$icon = "";
  	if ($weather eq "200") { $code = "18"; $icon = "tstorms" };
  	if ($weather eq "201") { $code = "18"; $icon = "tstorms" };
  	if ($weather eq "202") { $code = "19"; $icon = "tstorms" };
  	if ($weather eq "210") { $code = "18"; $icon = "tstorms" };
  	if ($weather eq "211") { $code = "18"; $icon = "tstorms" };
  	if ($weather eq "212") { $code = "19"; $icon = "tstorms" };
  	if ($weather eq "221") { $code = "19"; $icon = "tstorms" };
  	if ($weather eq "230") { $code = "18"; $icon = "tstorms" };
  	if ($weather eq "231") { $code = "18"; $icon = "tstorms" };
  	if ($weather eq "232") { $code = "19"; $icon = "tstorms" };
  	if ($weather eq "300") { $code = "13"; $icon = "chancerain" };
  	if ($weather eq "301") { $code = "13"; $icon = "chancerain" };
  	if ($weather eq "302") { $code = "13"; $icon = "chancerain" };
  	if ($weather eq "310") { $code = "10"; $icon = "chancerain" };
  	if ($weather eq "311") { $code = "11"; $icon = "rain" };
  	if ($weather eq "312") { $code = "12"; $icon = "rain" };
  	if ($weather eq "313") { $code = "12"; $icon = "rain" };
  	if ($weather eq "314") { $code = "12"; $icon = "rain" };
  	if ($weather eq "321") { $code = "12"; $icon = "rain" };
  	if ($weather eq "500") { $code = "10"; $icon = "chancerain" };
  	if ($weather eq "501") { $code = "11"; $icon = "rain" };
  	if ($weather eq "502") { $code = "12"; $icon = "rain" };
  	if ($weather eq "503") { $code = "12"; $icon = "rain" };
  	if ($weather eq "504") { $code = "12"; $icon = "rain" };
  	if ($weather eq "511") { $code = "14"; $icon = "sleet" };
  	if ($weather eq "520") { $code = "10"; $icon = "rain" };
  	if ($weather eq "521") { $code = "11"; $icon = "rain" };
  	if ($weather eq "522") { $code = "12"; $icon = "rain" };
  	if ($weather eq "531") { $code = "12"; $icon = "rain" };
  	if ($weather eq "600") { $code = "20"; $icon = "snow" };
  	if ($weather eq "601") { $code = "21"; $icon = "snow" };
  	if ($weather eq "602") { $code = "22"; $icon = "snow" };
  	if ($weather eq "611") { $code = "26"; $icon = "sleet" };
  	if ($weather eq "612") { $code = "28"; $icon = "sleet" };
  	if ($weather eq "613") { $code = "29"; $icon = "sleet" };
  	if ($weather eq "615") { $code = "23"; $icon = "sleet" };
  	if ($weather eq "616") { $code = "23"; $icon = "snow" };
  	if ($weather eq "620") { $code = "21"; $icon = "snow" };
  	if ($weather eq "621") { $code = "21"; $icon = "snow" };
  	if ($weather eq "622") { $code = "21"; $icon = "snow" };
  	if ($weather eq "701") { $code = "6";  $icon = "fog" };
  	if ($weather eq "711") { $code = "6";  $icon = "fog" };
  	if ($weather eq "721") { $code = "5";  $icon = "hazy" };
  	if ($weather eq "731") { $code = "6";  $icon = "fog" };
  	if ($weather eq "741") { $code = "6";  $icon = "fog" };
  	if ($weather eq "751") { $code = "6";  $icon = "fog" };
  	if ($weather eq "761") { $code = "6";  $icon = "fog" };
  	if ($weather eq "762") { $code = "6";  $icon = "fog" };
  	if ($weather eq "771") { $code = "19";  $icon = "tstorms" };
  	if ($weather eq "781") { $code = "19";  $icon = "tstorms" };
  	if ($weather eq "800") { $code = "1";  $icon = "clear" };
  	if ($weather eq "801") { $code = "2";  $icon = "mostlysunny" };
  	if ($weather eq "802") { $code = "3";  $icon = "mostlycloudy" };
  	if ($weather eq "803") { $code = "4";  $icon = "cloudy" };
  	if ($weather eq "804") { $code = "5";  $icon = "overcast" };
  	if (!$icon) { $icon = "rain" };
    if (!$code) { $code = "13" };
  	print F "$icon|";
  	print F "$code|";
		print F "$results->{weather}->{description}|";
		print F "-9999|";
		print F sprintf("%.0f",$results->{moon_phase}*100), "|";
		# Save today's moon phase to include it in current.dat
		if ($i eq "2") {
			$moonpercent = sprintf("%.0f",$results->{moon_phase}*100);
		}
		print F sprintf("%.1f",$results->{dewpt}), "|";
		print F sprintf("%.0f",$results->{pres}), "|";
		print F sprintf("%.1f",$results->{uv}),"|";
		$t = localtime($results->{sunrise_ts});
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		$t = localtime($results->{sunset_ts});
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		print F "$results->{vis}|";
		print F "\n";
	}
  flock(F,8);
close(F);

LOGOK "Saving daily forecast data to $lbplogdir/dailyforecast.dat.tmp successfully.";

LOGDEB "Database content:";
open(F,"<$lbplogdir/dailyforecast.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
		LOGDEB "$_";
	}
close (F);

} # end Daily

if ($hourly) { # Start Hourly

# Saving new hourly forecast data...

# Get data from Weatherbit Server (API request) for current conditions
my $queryurlcr = "$url/forecast/hourly?key=$apikey&$stationid&lang=$lang&units=M&marine=f&hours=120";

LOGINF "Fetching Hourly Forecat Data for Location $stationid";
LOGDEB "URL: $queryurlcr";

my $ua = new LWP::UserAgent;
my $res = $ua->get($queryurlcr);
my $json = $res->decoded_content();

# Check status of request
my $urlstatus = $res->status_line;
my $urlstatuscode = substr($urlstatus,0,3);

LOGDEB "Status: $urlstatus";

if ($urlstatuscode ne "200") {
  LOGCRIT "Failed to fetch data for $stationid\. Status Code: $urlstatuscode";
  exit 2;
} else {
  LOGOK "Data fetched successfully for $stationid";
}

# Decode JSON response from server
my $decoded_json = decode_json( "$json" );

$error = 0;
open(F,">$lbplogdir/hourlyforecast.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/hourlyforecast.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	$i = 1;
	my $n = 0;
	for my $results( @{$decoded_json->{data}} ){
		# Skip first dataset (eq to current)
		#if ($n eq "0") {
		#	$n++;
		#	next;
		#}
		print F "$i|";
		$i++;
		print F $results->{ts}, "|";
		$t = localtime($results->{ts});
		print F sprintf("%02d", $t->mday), "|";
		print F sprintf("%02d", $t->mon), "|";
		my @month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		@month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		print F $t->year . "|";
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		my @days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		@days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		print F sprintf("%.1f",$results->{temp}), "|";
		print F sprintf("%.1f",$results->{app_temp}), "|";
		print F "-9999|";
		print F "$results->{rh}|";
		$wdir = $results->{wind_dir};
		if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
		if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
		if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
		if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
		if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
		if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
		if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
		if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		print F "$wdirdes|";
		print F "$results->{wind_dir}|";
		print F sprintf("%.1f",$results->{wind_spd} * 3.6), "|";
		#print F sprintf("%.1f",$results->{wind_gust_spd} * 3.6), "|";
		print F sprintf("%.1f",$results->{app_temp}), "|";
		print F sprintf("%.0f",$results->{pres}), "|";
		print F sprintf("%.1f",$results->{dewpt}), "|";
		print F "$results->{clouds}|";
		print F "-9999|";
		print F sprintf("%.1f",$results->{uv}), "|";
		print F sprintf("%.3f",$results->{precip}), "|";
		print F sprintf("%.3f",$results->{snow}), "|";
		print F "$results->{pop}|";
		# Convert Weather string into Weather Code and convert icon name
		$weather = $results->{weather}->{code};
  	$code = "";
  	$icon = "";
  	if ($weather eq "200") { $code = "18"; $icon = "tstorms" };
  	if ($weather eq "201") { $code = "18"; $icon = "tstorms" };
  	if ($weather eq "202") { $code = "19"; $icon = "tstorms" };
  	if ($weather eq "210") { $code = "18"; $icon = "tstorms" };
  	if ($weather eq "211") { $code = "18"; $icon = "tstorms" };
  	if ($weather eq "212") { $code = "19"; $icon = "tstorms" };
  	if ($weather eq "221") { $code = "19"; $icon = "tstorms" };
  	if ($weather eq "230") { $code = "18"; $icon = "tstorms" };
  	if ($weather eq "231") { $code = "18"; $icon = "tstorms" };
  	if ($weather eq "232") { $code = "19"; $icon = "tstorms" };
  	if ($weather eq "300") { $code = "13"; $icon = "chancerain" };
  	if ($weather eq "301") { $code = "13"; $icon = "chancerain" };
  	if ($weather eq "302") { $code = "13"; $icon = "chancerain" };
  	if ($weather eq "310") { $code = "10"; $icon = "chancerain" };
  	if ($weather eq "311") { $code = "11"; $icon = "rain" };
  	if ($weather eq "312") { $code = "12"; $icon = "rain" };
  	if ($weather eq "313") { $code = "12"; $icon = "rain" };
  	if ($weather eq "314") { $code = "12"; $icon = "rain" };
  	if ($weather eq "321") { $code = "12"; $icon = "rain" };
  	if ($weather eq "500") { $code = "10"; $icon = "chancerain" };
  	if ($weather eq "501") { $code = "11"; $icon = "rain" };
  	if ($weather eq "502") { $code = "12"; $icon = "rain" };
  	if ($weather eq "503") { $code = "12"; $icon = "rain" };
  	if ($weather eq "504") { $code = "12"; $icon = "rain" };
  	if ($weather eq "511") { $code = "14"; $icon = "sleet" };
  	if ($weather eq "520") { $code = "10"; $icon = "rain" };
  	if ($weather eq "521") { $code = "11"; $icon = "rain" };
  	if ($weather eq "522") { $code = "12"; $icon = "rain" };
  	if ($weather eq "531") { $code = "12"; $icon = "rain" };
  	if ($weather eq "600") { $code = "20"; $icon = "snow" };
  	if ($weather eq "601") { $code = "21"; $icon = "snow" };
  	if ($weather eq "602") { $code = "22"; $icon = "snow" };
  	if ($weather eq "611") { $code = "26"; $icon = "sleet" };
  	if ($weather eq "612") { $code = "28"; $icon = "sleet" };
  	if ($weather eq "613") { $code = "29"; $icon = "sleet" };
  	if ($weather eq "615") { $code = "23"; $icon = "sleet" };
  	if ($weather eq "616") { $code = "23"; $icon = "snow" };
  	if ($weather eq "620") { $code = "21"; $icon = "snow" };
  	if ($weather eq "621") { $code = "21"; $icon = "snow" };
  	if ($weather eq "622") { $code = "21"; $icon = "snow" };
  	if ($weather eq "701") { $code = "6";  $icon = "fog" };
  	if ($weather eq "711") { $code = "6";  $icon = "fog" };
  	if ($weather eq "721") { $code = "5";  $icon = "hazy" };
  	if ($weather eq "731") { $code = "6";  $icon = "fog" };
  	if ($weather eq "741") { $code = "6";  $icon = "fog" };
  	if ($weather eq "751") { $code = "6";  $icon = "fog" };
  	if ($weather eq "761") { $code = "6";  $icon = "fog" };
  	if ($weather eq "762") { $code = "6";  $icon = "fog" };
  	if ($weather eq "771") { $code = "19";  $icon = "tstorms" };
  	if ($weather eq "781") { $code = "19";  $icon = "tstorms" };
  	if ($weather eq "800") { $code = "1";  $icon = "clear" };
  	if ($weather eq "801") { $code = "2";  $icon = "mostlysunny" };
  	if ($weather eq "802") { $code = "3";  $icon = "mostlycloudy" };
  	if ($weather eq "803") { $code = "4";  $icon = "cloudy" };
  	if ($weather eq "804") { $code = "5";  $icon = "overcast" };
  	if (!$icon) { $icon = "rain" };
    if (!$code) { $code = "13" };
  	print F "$icon|";
  	print F "$code|";
		print F "$results->{weather}->{description}|";
		print F "$results->{ozone}|";
		print F "$results->{ghi}|";
		print F "$results->{vis}|";
		print F "\n";
	}
  flock(F,8);
close(F);

LOGOK "Saving hourly forecast data to $lbplogdir/hourlyforecast.dat.tmp successfully.";

LOGDEB "Database content:";
open(F,"<$lbplogdir/hourlyforecast.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
		LOGDEB "$_";
	}
close (F);

} # End Hourly

# Clean Up Databases

if ($current) {

LOGINF "Cleaning $lbplogdir/current.dat.tmp";
open(F,"+<$lbplogdir/current.dat.tmp");
  flock(F,2);
	@filecontent = <F>;
	seek(F,0,0);
	truncate(F,0);
	foreach (@filecontent){
		s/[\n\r]//g;
		if($_ =~ /^#/) {
		  print F "$_\n";
		  next;
		}
		LOGDEB "Original: $_";
		s/\|null\|/"|0|"/eg;
		s/\|--\|/"|0|"/eg;
		s/\|na\|/"|-9999.00|"/eg;
		s/\|NA\|/"|-9999.00|"/eg;
		s/\|n\/a\|/"|-9999.00|"/eg;
		s/\|N\/A\|/"|-9999.00|"/eg;
		if ($moonpercent) {
			s/\|MOONPERCENT\|/"|$moonpercent|"/eg;
		}
		LOGDEB "Cleaned:  $_";
		print F "$_\n";
	}
  flock(F,8);
close(F);

my $currentname = "$lbplogdir/current.dat.tmp";
my $currentsize = -s ($currentname);
if ($currentsize > 100) {
        move($currentname, "$lbplogdir/current.dat");
}

}

if ($daily) {

LOGINF "Cleaning $lbplogdir/dailyforecast.dat.tmp";
open(F,"+<$lbplogdir/dailyforecast.dat.tmp");
  flock(F,2);
	@filecontent = <F>;
	seek(F,0,0);
	truncate(F,0);
	foreach (@filecontent){
		s/[\n\r]//g;
		if($_ =~ /^#/) {
		  print F "$_\n";
		  next;
		}
		LOGDEB "Original: $_";
		s/\|null\|/"|0|"/eg;
		s/\|--\|/"|0|"/eg;
		s/\|na\|/"|-9999.00|"/eg;
		s/\|NA\|/"|-9999.00|"/eg;
		s/\|n\/a\|/"|-9999.00|"/eg;
		s/\|N\/A\|/"|-9999.00|"/eg;
		LOGDEB "Cleaned:  $_";
		print F "$_\n";
	}
  flock(F,8);
close(F);

my $dailyname = "$lbplogdir/dailyforecast.dat.tmp";
my $dailysize = -s ($dailyname);
if ($dailysize > 100) {
        move($dailyname, "$lbplogdir/dailyforecast.dat");
}

}

if ($hourly) {

LOGINF "Cleaning $lbplogdir/hourlyforecast.dat.tmp";
open(F,"+<$lbplogdir/hourlyforecast.dat.tmp");
  flock(F,2);
	@filecontent = <F>;
	seek(F,0,0);
	truncate(F,0);
	foreach (@filecontent){
		s/[\n\r]//g;
		if($_ =~ /^#/) {
		  print F "$_\n";
		  next;
		}
		LOGDEB "Original: $_";
		s/\|null\|/"|0|"/eg;
		s/\|--\|/"|0|"/eg;
		s/\|na\|/"|-9999.00|"/eg;
		s/\|NA\|/"|-9999.00|"/eg;
		s/\|n\/a\|/"|-9999.00|"/eg;
		s/\|N\/A\|/"|-9999.00|"/eg;
		LOGDEB "Cleaned:  $_";
		print F "$_\n";
	}
  flock(F,8);
close(F);

my $hourlyname = "$lbplogdir/hourlyforecast.dat.tmp";
my $hourlysize = -s ($hourlyname);
if ($hourlysize > 100) {
        move($hourlyname, "$lbplogdir/hourlyforecast.dat");
}

}

# Give OK status to client.
LOGOK "Current Data and Forecasts saved successfully.";

# Exit
exit;

END
{
	LOGEND;
}
