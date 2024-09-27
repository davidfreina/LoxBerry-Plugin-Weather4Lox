#!/usr/bin/perl

# grabber for fetching data from GeoSphere Austria
# fetches weather data (current and forecast) from geosphere.at

# Copyright 2016-2024 Michael Schlenstedt, michael@loxberry.de
# Copyright 2024 David Freina, david@freina.at
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
use Math::Function::Interpolator;
#use Data::Dumper;

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = LoxBerry::System::pluginversion();

my $pcfg		= new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $url			= $pcfg->param("GEOSPHEREAUSTRIA.URL");
my $stationid	= $pcfg->param("GEOSPHEREAUSTRIA.STATIONID");
my $city		= $pcfg->param("GEOSPHEREAUSTRIA.CITY");
my $country		= $pcfg->param("GEOSPHEREAUSTRIA.COUNTRY");

# Read language phrases
my %L = LoxBerry::System::readlanguage("language.ini");

# Create a logging object
my $log = LoxBerry::Log->new (
	package => 'weather4lox',
	name => 'grabber_geosphere_austria.in',
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

if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

LOGSTART "Weather4Lox GRABBER_GEOSPHERE_AUSTRIA process started";
LOGDEB "This is $0 Version $version";

# Fetch data from dataset.api.hub.geosphere.at
# current conditions
my $queryurlcr = "$url/station/current/tawes-v1-10min?station_ids=$stationid&parameters=RF&parameters=TL&parameters=DD&parameters=FF&parameters=FFX&parameters=RR&parameters=P&parameters=TP&parameters=GLOW&output_format=geojson";

my $error = 0;
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
  LOGCRIT "Failed to fetch current data for $stationid\. Status Code: $urlstatuscode";
  exit 2;
} else {
  LOGOK "Current data fetched successfully for $stationid";
}

# Fetch data from dataset.api.hub.geosphere.at
# daily
my $queryurldaily = "$url/timeseries/forecast/nwp-v1-1h-2500m?parameters=RR&station_ids=$stationid&output_format=geojson";

$error = 0;
LOGINF "Fetching Daily Forecast Data for Location $stationid";
LOGDEB "URL: $queryurldaily";

$res = $ua->get($queryurldaily);
my $json_daily = $res->decoded_content();

# Check status of request
$urlstatus = $res->status_line;
$urlstatuscode = substr($urlstatus,0,3);

LOGDEB "Status: $urlstatus";

if ($urlstatuscode ne "200") {
  LOGCRIT "Failed to fetch daily forecast data for $stationid\. Status Code: $urlstatuscode";
  exit 2;
} else {
  LOGOK "Daily forecast data fetched successfully for $stationid";
}

# Decode JSON response from server
my $decoded_json_daily = decode_json( "$json_daily" );

my $t;
my $weather;
my $code;
my $icon;
my $wdir;
my $wdirdes;
my @filecontent;
my $i;

#
# Fetch current data
#

if ( $current ) { # Start current
	# Write location data into database
	my $t = Time::Piece->strptime($decoded_json->{timestamps}[0], "%Y-%m-%dT%R");
	LOGINF "Saving new Data for Timestamp $t to database.";
	# Saving new current data...
	$error = 0;
	open(F,">$lbplogdir/current.dat.tmp") or $error = 1;
	flock(F,2);
		if ($error) {
			LOGCRIT "Cannot open $lbpconfigdir/current.dat.tmp";
			exit 2;
		}
		binmode F, ':encoding(UTF-8)';
		print F $t->epoch . "|";																									# 0
		print F "$t|";																												# 1
		my $tz_short = qx(date +%Z);
		chomp ($tz_short);
		print F "$tz_short|";																										# 2
		my $tz_long = qx(cat /etc/timezone);
		chomp ($tz_long);
		print F "$tz_long|";																										# 3
		my $tz_offset = qx(date +%z);
		chomp ($tz_offset);
		print F "$tz_offset|";																										# 4
		my $city = Encode::decode("UTF-8", $city);
		print F "$city|";																											# 5
		my $country = Encode::decode("UTF-8", $country);
		print F "$country|";																										# 6
		print F "-9999|";																											# 7
		print F "$decoded_json->{features}[0]->{geometry}->{coordinates}->{1}|";													# 8
		print F "$decoded_json->{features}[0]->{geometry}->{coordinates}->{0}|";													# 9
		print F "-9999|";																											# 10
		print F sprintf("%.1f",$decoded_json->{features}[0]->{properties}->{parameters}->{TL}->{data}[0]), "|";						# 11
		print F "-9999|";																											# 12
		print F sprintf("%.0f",$decoded_json->{features}[0]->{properties}->{parameters}->{RF}->{data}[0]), "|";						# 13
		$wdirdeg = $decoded_json->{features}[0]->{properties}->{parameters}->{DD}->{data}[0];
		if ( $wdirdeg >= 0 	&& $wdirdeg <= 	22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		if ( $wdirdeg > 22 	&& $wdirdeg <= 	68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
		if ( $wdirdeg > 68 	&& $wdirdeg <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
		if ( $wdirdeg > 112 && $wdirdeg <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
		if ( $wdirdeg > 158 && $wdirdeg <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
		if ( $wdirdeg > 202 && $wdirdeg <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
		if ( $wdirdeg > 248 && $wdirdeg <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
		if ( $wdirdeg > 292 && $wdirdeg <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
		if ( $wdirdeg > 338 && $wdirdeg <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		print F "$wdirdes|";																										# 14
		print F "$wdirdeg|";																										# 15
		print F sprintf("%.0f",$decoded_json->{features}[0]->{properties}->{parameters}->{FF}->{data}[0]), "|";						# 16
		print F sprintf("%.0f",$decoded_json->{features}[0]->{properties}->{parameters}->{FFX}->{data}[0]), "|";					# 17
		print F "-9999|";																											# 18
		print F sprintf("%.0f",$decoded_json->{features}[0]->{properties}->{parameters}->{P}->{data}[0]), "|";						# 19
		print F sprintf("%.1f",$decoded_json->{features}[0]->{properties}->{parameters}->{TP}->{data}[0]), "|";						# 20
		print F "-9999|";																											# 21
		print F sprintf("%.0f",$decoded_json->{features}[0]->{properties}->{parameters}->{GLOW}->{data}[0]), "|";					# 22
		print F "-9999|";																											# 23
		print F "-9999|";																											# 24
		print F "-9999|";																											# 25
		print F sprintf("%.0f",$decoded_json->{features}[0]->{properties}->{parameters}->{RR}->{data}[0]), "|";						# 26
		# Convert Weather string into Weather Code and convert icon name
		$weather = $decoded_json->{current_condition}[0]->{weatherCode};
		$code = "";
		$icon = "";
		if ($weather eq "113") { $code = "1"; $icon = "sunny" };
		if ($weather eq "116") { $code = "2"; $icon = "partlycloudy" };
		if ($weather eq "119") { $code = "4"; $icon = "cloudy" };
		if ($weather eq "122") { $code = "4"; $icon = "cloudy" };
		if ($weather eq "143") { $code = "6"; $icon = "fog" };
		if ($weather eq "176") { $code = "10"; $icon = "rain" };
		if ($weather eq "179") { $code = "18"; $icon = "sleet" };
		if ($weather eq "182") { $code = "18"; $icon = "sleet" };
		if ($weather eq "185") { $code = "18"; $icon = "sleet" };
		if ($weather eq "200") { $code = "15"; $icon = "tstorms" };
		if ($weather eq "227") { $code = "21"; $icon = "snow" };
		if ($weather eq "230") { $code = "21"; $icon = "snow" };
		if ($weather eq "248") { $code = "6"; $icon = "fog" };
		if ($weather eq "260") { $code = "6"; $icon = "fog" };
		if ($weather eq "263") { $code = "10"; $icon = "rain" };
		if ($weather eq "266") { $code = "12"; $icon = "rain" };
		if ($weather eq "281") { $code = "19"; $icon = "sleet" };
		if ($weather eq "284") { $code = "19"; $icon = "sleet" };
		if ($weather eq "293") { $code = "12"; $icon = "rain" };
		if ($weather eq "296") { $code = "12"; $icon = "rain" };
		if ($weather eq "299") { $code = "13"; $icon = "rain" };
		if ($weather eq "302") { $code = "13"; $icon = "rain" };
		if ($weather eq "305") { $code = "13"; $icon = "rain" };
		if ($weather eq "308") { $code = "13"; $icon = "rain" };
		if ($weather eq "311") { $code = "19"; $icon = "sleet" };
		if ($weather eq "314") { $code = "19"; $icon = "sleet" };
		if ($weather eq "317") { $code = "19"; $icon = "sleet" };
		if ($weather eq "320") { $code = "20"; $icon = "snow" };
		if ($weather eq "323") { $code = "20"; $icon = "sleet" };
		if ($weather eq "326") { $code = "20"; $icon = "sleet" };
		if ($weather eq "329") { $code = "21"; $icon = "snow" };
		if ($weather eq "332") { $code = "21"; $icon = "snow" };
		if ($weather eq "335") { $code = "21"; $icon = "snow" };
		if ($weather eq "338") { $code = "21"; $icon = "snow" };
		if ($weather eq "350") { $code = "18"; $icon = "sleet" };
		if ($weather eq "353") { $code = "12"; $icon = "rain" };
		if ($weather eq "356") { $code = "13"; $icon = "rain" };
		if ($weather eq "359") { $code = "13"; $icon = "rain" };
		if ($weather eq "362") { $code = "18"; $icon = "sleet" };
		if ($weather eq "365") { $code = "18"; $icon = "sleet" };
		if ($weather eq "368") { $code = "20"; $icon = "sleet" };
		if ($weather eq "371") { $code = "21"; $icon = "sleet" };
		if ($weather eq "374") { $code = "18"; $icon = "sleet" };
		if ($weather eq "377") { $code = "18"; $icon = "sleet" };
		if ($weather eq "386") { $code = "15"; $icon = "tstorms" };
		if ($weather eq "389") { $code = "15"; $icon = "tstorms" };
		if ($weather eq "392") { $code = "15"; $icon = "tstorms" };
		if ($weather eq "395") { $code = "16"; $icon = "sleet" };
		if (!$icon) { $icon = "clear" };
		if (!$code) { $code = "1" };
		print F "-9999|";																											# 27
		print F "-9999|";																											# 28
		my $wdes = $decoded_json->{current_condition}[0]->{'lang_' . $lang}[0]{value};
		$wdes = $decoded_json->{current_condition}[0]->{weatherDesc}[0]{value} if !$wdes;
		print F "$wdes|";																											# 29
		print F "$decoded_json->{weather}[0]->{astronomy}[0]{moon_illumination}|";													# 30
		print F "-9999|";																											# 31
		my $moonphasen;
		my $moonphase = lc( $decoded_json->{weather}[0]->{astronomy}[0]{moon_phase} );
		if ( $moonphase eq "new moon" ) {
			$moonphasen = 0;
		} elsif ( $moonphase eq "waxing crescent" ) {
			$moonphasen = 0.125;
		} elsif ( $moonphase eq "first quarter" ) {
			$moonphasen = 0.25;
		} elsif ( $moonphase eq "waxing gibbous" ) {
			$moonphasen = 0.375;
		} elsif ( $moonphase eq "full moon" ) {
			$moonphasen = 0.5;
		} elsif ( $moonphase eq "waning gibbous" ) {
			$moonphasen = 0.625;
		} elsif ( $moonphase eq "last quarter" ) {
			$moonphasen = 0.75;
		} elsif ( $moonphase eq "waning crescent" ) {
			$moonphasen = 0.875;
		} else {
			$moonphasen = 1;
		}
		print F sprintf("%.0f",$moonphasen*100), "|";																				# 32
		print F "-9999|";																											# 33
		# $t = Time::Piece->strptime($decoded_json->{weather}[0]->{astronomy}[0]{sunrise}, "%R %p");
		print F sprintf("%02d", $t->hour), "|";																						# 34
		print F sprintf("%02d", $t->min), "|";																						# 35
		# $t = Time::Piece->strptime($decoded_json->{weather}[0]->{astronomy}[0]{sunset}, "%R %p");
		print F sprintf("%02d", $t->hour), "|";																						# 36
		print F sprintf("%02d", $t->min), "|";																						# 37
		print F "-9999|";																											# 38
		print F "$decoded_json->{current_condition}[0]->{cloudcover}|";																# 39
		print F "-9999|";																											# 40
		print F sprintf("%.0f",$decoded_json->{features}[0]->{properties}->{parameters}->{SCHNEE}->{data}[0]), "|";					# 41
		print F "\n";
	flock(F,8);
	close(F);

	LOGOK "Saving current data to $lbplogdir/current.dat.tmp successfully.";

	LOGDEB "Database content:";
	open(F,"<$lbplogdir/current.dat.tmp");
		@filecontent = <F>;
		foreach (@filecontent) {
			chomp ($_);
			LOGDEB "$_";
		}
	close (F);
} # End current

#
# Fetch daily data
#

if ( $daily ) { # Start daily

# Saving new daily forecast data...
	open(F,">$lbplogdir/dailyforecast.dat.tmp") or $error = 1;
	flock(F,2);
		if ($error) {
			LOGCRIT "Cannot open $lbplogdir/dailyforecast.dat.tmp";
			exit 2;
		}
		binmode F, ':encoding(UTF-8)';
		my $i = 1;
		# TODO: Change iteration, currently iterates over hourly timestamps
		for my $results( @{$decoded_json_daily->{timestamps}} ){
			print F "$i|";
			$i++;
			$t = Time::Piece->strptime($results->{date}, "%Y-%m-%d");
			print F $t->epoch, "|";
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
			print F sprintf("%.1f",$results->{maxtempC}), "|";
			print F sprintf("%.1f",$results->{mintempC}), "|";
			# Figure out min/max/sum values for daily forecast from hourly values
			my @pops;
			my $prec = 0;
			my @gusts;
			my @winds;
			my @winddirs;
			my @hums;
			my @pressures;
			my @dewps;
			my @visibilitys;
			for my $hourly ( @{$results->{hourly}} ){
				if ( $hourly->{chanceofrain} ) {
					push ( @pops, $hourly->{chanceofrain} );
				}
				if ( $hourly->{precipMM} ) {
					$prec += $hourly->{precipMM} * 3; # 3 hourly FC
				}
				if ( $hourly->{WindGustKmph} ) {
					push ( @gusts, $hourly->{WindGustKmph} );
				}
				if ( $hourly->{windspeedKmph} ) {
					push ( @winds, $hourly->{windspeedKmph} );
				}
				if ( $hourly->{winddirDegree} ) {
					push ( @winddirs, $hourly->{winddirDegree} );
				}
				if ( $hourly->{humidity} ) {
					push ( @hums, $hourly->{humidity} );
				}
				if ( $hourly->{pressure} ) {
					push ( @pressures, $hourly->{pressure} );
				}
				if ( $hourly->{DewPointC} ) {
					push ( @dewps, $hourly->{DewPointC} );
				}
				if ( $hourly->{visibility} ) {
					push ( @visibilitys, $hourly->{visibility} );
				}
			}
			@pops = sort { $a <=> $b } @pops;
			if ($pops[-1]) { # Max from sorted array
				print F sprintf("%.0f",$pops[-1]), "|";
			} else {
				print F "0|";
			}
			if ($prec) {
				print F sprintf("%.2f",$prec), "|";
			} else {
				print F "0|";
			}
			print F sprintf("%.1f",$results->{totalSnow_cm}), "|";
			if ($gusts[-1]) { # Max from sorted array
				print F sprintf("%.0f",$gusts[-1]), "|";
			} else {
				print F "0|";
			}
			print F "-9999|";
			print F "-9999|";
			my $windavg = eval(join("+", @winds)) / @winds; # Mean from array
			if ($windavg) {
				print F sprintf("%.0f",$windavg), "|";
			} else {
				print F "0|";
			}
			my $wdir = 0;
			$wdir = eval(join("+", @winddirs)) / @winddirs; # Mean from array
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
			print F "$wdir|";
			my $humidity = eval(join("+", @hums)) / @hums; # Mean from array
			print F sprintf("%.0f",$humidity), "|";
			if ($hums[-1]) { # Max from sorted array
				print F sprintf("%.0f",$hums[-1]), "|";
			} else {
				print F "0|";
			}
			if ($hums[0]) { # Min from sorted array
				print F sprintf("%.0f",$hums[0]), "|";
			} else {
				print F "0|";
			}
			# Convert Weather string into Weather Code and convert icon name: We do not have an average, so we take value from 12 o'clock
			$weather = $results->{hourly}[4]->{weatherCode};
			$code = "";
			$icon = "";
			if ($weather eq "113") { $code = "1"; $icon = "sunny" };
			if ($weather eq "116") { $code = "2"; $icon = "partlycloudy" };
			if ($weather eq "119") { $code = "4"; $icon = "cloudy" };
			if ($weather eq "122") { $code = "4"; $icon = "cloudy" };
			if ($weather eq "143") { $code = "6"; $icon = "fog" };
			if ($weather eq "176") { $code = "10"; $icon = "rain" };
			if ($weather eq "179") { $code = "18"; $icon = "sleet" };
			if ($weather eq "182") { $code = "18"; $icon = "sleet" };
			if ($weather eq "185") { $code = "18"; $icon = "sleet" };
			if ($weather eq "200") { $code = "15"; $icon = "tstorms" };
			if ($weather eq "227") { $code = "21"; $icon = "snow" };
			if ($weather eq "230") { $code = "21"; $icon = "snow" };
			if ($weather eq "248") { $code = "6"; $icon = "fog" };
			if ($weather eq "260") { $code = "6"; $icon = "fog" };
			if ($weather eq "263") { $code = "10"; $icon = "rain" };
			if ($weather eq "266") { $code = "12"; $icon = "rain" };
			if ($weather eq "281") { $code = "19"; $icon = "sleet" };
			if ($weather eq "284") { $code = "19"; $icon = "sleet" };
			if ($weather eq "293") { $code = "12"; $icon = "rain" };
			if ($weather eq "296") { $code = "12"; $icon = "rain" };
			if ($weather eq "299") { $code = "13"; $icon = "rain" };
			if ($weather eq "302") { $code = "13"; $icon = "rain" };
			if ($weather eq "305") { $code = "13"; $icon = "rain" };
			if ($weather eq "308") { $code = "13"; $icon = "rain" };
			if ($weather eq "311") { $code = "19"; $icon = "sleet" };
			if ($weather eq "314") { $code = "19"; $icon = "sleet" };
			if ($weather eq "317") { $code = "19"; $icon = "sleet" };
			if ($weather eq "320") { $code = "20"; $icon = "snow" };
			if ($weather eq "323") { $code = "20"; $icon = "sleet" };
			if ($weather eq "326") { $code = "20"; $icon = "sleet" };
			if ($weather eq "329") { $code = "21"; $icon = "snow" };
			if ($weather eq "332") { $code = "21"; $icon = "snow" };
			if ($weather eq "335") { $code = "21"; $icon = "snow" };
			if ($weather eq "338") { $code = "21"; $icon = "snow" };
			if ($weather eq "350") { $code = "18"; $icon = "sleet" };
			if ($weather eq "353") { $code = "12"; $icon = "rain" };
			if ($weather eq "356") { $code = "13"; $icon = "rain" };
			if ($weather eq "359") { $code = "13"; $icon = "rain" };
			if ($weather eq "362") { $code = "18"; $icon = "sleet" };
			if ($weather eq "365") { $code = "18"; $icon = "sleet" };
			if ($weather eq "368") { $code = "20"; $icon = "sleet" };
			if ($weather eq "371") { $code = "21"; $icon = "sleet" };
			if ($weather eq "374") { $code = "18"; $icon = "sleet" };
			if ($weather eq "377") { $code = "18"; $icon = "sleet" };
			if ($weather eq "386") { $code = "15"; $icon = "tstorms" };
			if ($weather eq "389") { $code = "15"; $icon = "tstorms" };
			if ($weather eq "392") { $code = "15"; $icon = "tstorms" };
			if ($weather eq "395") { $code = "16"; $icon = "sleet" };
			if (!$icon) { $icon = "clear" };
			if (!$code) { $code = "1" };
			print F "$icon|";
			print F "$code|";
			my $wdes = "";
			$wdes = $results->{hourly}[4]->{'lang_' . $lang}[0]{value};
			$wdes = $results->{hourly}[4]->{weatherDesc}[0]{value} if !$wdes;
			print F "$wdes|";
			my $moonphasen = "";
			my $moonphase = lc( $results->{astronomy}[0]{moon_phase} );
			if ( $moonphase eq "new moon" ) {
				$moonphasen = 0;
			} elsif ( $moonphase eq "waxing crescent" ) {
				$moonphasen = 0.125;
			} elsif ( $moonphase eq "first quarter" ) {
				$moonphasen = 0.25;
			} elsif ( $moonphase eq "waxing gibbous" ) {
				$moonphasen = 0.375;
			} elsif ( $moonphase eq "full moon" ) {
				$moonphasen = 0.5;
			} elsif ( $moonphase eq "waning gibbous" ) {
				$moonphasen = 0.625;
			} elsif ( $moonphase eq "last quarter" ) {
				$moonphasen = 0.75;
			} elsif ( $moonphase eq "waning crescent" ) {
				$moonphasen = 0.875;
			} else {
				$moonphasen = 1;
			}
			print F sprintf("%.0f",$moonphasen*100), "|";
			my $dewp = eval(join("+", @dewps)) / @dewps; # Mean from array
			print F sprintf("%.1f",$dewp), "|";
			my $pressure = eval(join("+", @pressures)) / @pressures; # Mean from array
			print F sprintf("%.1f",$pressure), "|";
			print F sprintf("%.1f",$results->{uvIndex}),"|";
			$t = Time::Piece->strptime($results->{astronomy}[0]{sunrise}, "%R %p");
			print F sprintf("%02d", $t->hour), "|";
			print F sprintf("%02d", $t->min), "|";
			$t = Time::Piece->strptime($results->{astronomy}[0]{sunset}, "%R %p");
			print F sprintf("%02d", $t->hour), "|";
			print F sprintf("%02d", $t->min), "|";
			my $vis = eval(join("+", @visibilitys)) / @visibilitys; # Mean from array
			print F sprintf("%.1f",$vis), "|";
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

} # End daily

#
# Fetch hourly data
#

if ( $hourly ) { # Start hourly

# Parse data for hourly data
my %temps;
my $temps;
my %fltemps;
my $fltemps;
my %hums;
my $hums;
my %winddirs;
my $winddirs;
my %winds;
my $winds;
my %gusts;
my $gusts;
my %pressures;
my $pressures;
my %dewps;
my $dewps;
my %clouds;
my $clouds;
my %uvis;
my $uvis;
my %his;
my $his;
my %precs;
my $precs;
my %codes;
my %weatherdess;
my %viss;
my $viss;
my %pops;
my $pops;
my @epoches;
for my $daily( @{$decoded_json->{weather}} ){
	for my $hourly( @{$daily->{hourly}} ){
		my $datetime = $daily->{date} . " " . $hourly->{time}/100 . ":00";
		$t = Time::Piece->strptime($datetime, "%Y-%m-%d %H:%M");
		my $ep = $t->epoch;
		push ( @epoches, $ep );
		$temps{$ep} = $hourly->{tempC};
		$temps = Math::Function::Interpolator::Linear->new( points => \%temps );
		$fltemps{$ep} = $hourly->{FeelsLikeC};
		$fltemps = Math::Function::Interpolator::Linear->new( points => \%fltemps );
		$hums{$ep} = $hourly->{humidity};
		$hums = Math::Function::Interpolator::Linear->new( points => \%hums );
		$winddirs{$ep} = $hourly->{winddirDegree};
		$winddirs = Math::Function::Interpolator::Linear->new( points => \%winddirs );
		$winds{$ep} = $hourly->{windspeedKmph};
		$winds = Math::Function::Interpolator::Linear->new( points => \%winds );
		$gusts{$ep} = $hourly->{WindGustKmph};
		$gusts = Math::Function::Interpolator::Linear->new( points => \%gusts );
		$pressures{$ep} = $hourly->{pressure};
		$pressures = Math::Function::Interpolator::Linear->new( points => \%pressures );
		$dewps{$ep} = $hourly->{DewPointC};
		$dewps = Math::Function::Interpolator::Linear->new( points => \%dewps );
		$clouds{$ep} = $hourly->{cloudcover};
		$clouds = Math::Function::Interpolator::Linear->new( points => \%clouds );
		$uvis{$ep} = $hourly->{uvIndex};
		$uvis = Math::Function::Interpolator::Linear->new( points => \%uvis );
		$his{$ep} = $hourly->{HeatIndexC};
		$his = Math::Function::Interpolator::Linear->new( points => \%his );
		$precs{$ep} = $hourly->{precipMM};
		$precs = Math::Function::Interpolator::Linear->new( points => \%precs );
		$pops{$ep} = $hourly->{chanceofrain};
		$pops = Math::Function::Interpolator::Linear->new( points => \%pops );
		$codes{$ep} = $hourly->{weatherCode};
		if ($hourly->{'lang_' . $lang}[0]->{value}) {
			$weatherdess{$ep} = $hourly->{'lang_' . $lang}[0]->{value};
		} else {
			$weatherdess{$ep} = $hourly->{weatherDesc}[0]->{value};
		}
		$viss{$ep} = $hourly->{visibility};
		$viss = Math::Function::Interpolator::Linear->new( points => \%viss );
	}
}

# Saving new hourly forecast data...
open(F,">$lbplogdir/hourlyforecast.dat.tmp") or $error = 1;
  flock(F,2);
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/hourlyforecast.dat.tmp";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	# Create hourly data set with interpolation from 3-hourly data
	my $now = time();
	@epoches = sort { $a <=> $b } @epoches;
	my $startep = $epoches[0];
	my $endep = $epoches[-1];
	my $i = 1;
	my $ep;
	my $newline;
	for ($ep = $startep; $ep <= $endep; $ep += 3600 ) { # Step is 3600s
		$newline = "";
		next if $now >= $ep; # data is too old
		$newline = $newline . sprintf("%.1f", $temps->linear($ep)) . "|";
		$newline = $newline . sprintf("%.1f", $fltemps->linear($ep)) . "|";
		$newline = $newline . sprintf("%.1f", $his->linear($ep)) . "|";
		$newline = $newline . sprintf("%.0f", $hums->linear($ep)) . "|";
		my $wdir = 0;
		$wdir = $winddirs->linear($ep);
		if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NE'}) }; # NorthEast
		if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_E'}) }; # East
		if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SE'}) }; # SouthEast
		if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_S'}) }; # South
		if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_SW'}) }; # SouthWest
		if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_W'}) }; # West
		if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_NW'}) }; # NorthWest
		if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = Encode::decode("UTF-8", $L{'GRABBER.LABEL_N'}) }; # North
		$newline = $newline . $wdirdes . "|";
		$newline = $newline . sprintf("%.1f", $wdir) . "|";
		$newline = $newline . sprintf("%.1f", $winds->linear($ep)) . "|";
		$newline = $newline . sprintf("%.1f", $fltemps->linear($ep)) . "|";
		$newline = $newline . sprintf("%.1f", $pressures->linear($ep)) . "|";
		$newline = $newline . sprintf("%.1f", $dewps->linear($ep)) . "|";
		$newline = $newline . sprintf("%.0f", $clouds->linear($ep)) . "|";
		$newline = $newline . "-9999" . "|";
		$newline = $newline . sprintf("%.0f", $uvis->linear($ep)) . "|";
		$newline = $newline . sprintf("%.2f", $precs->linear($ep)) . "|";
		$newline = $newline . "-9999" . "|";
		$newline = $newline . sprintf("%.0f", $pops->linear($ep)) . "|";
		my $weather;
		my $weatherdes;
		if ( $codes{$ep} ) {
			$weather = $codes{$ep};
			$weatherdes = $weatherdess{$ep};
		} elsif ( $codes{$ep-3600} ) {
			$weather = $codes{$ep-3600};
			$weatherdes = $weatherdess{$ep-3600};
		} elsif ( $codes{$ep+3600} ) {
			$weather = $codes{$ep+3600};
			$weatherdes = $weatherdess{$ep+3600};
		} elsif ( $codes{$ep-7200} ) {
			$weather = $codes{$ep-7200};
			$weatherdes = $weatherdess{$ep-7200};
		}
		$code = "";
		$icon = "";
		if ($weather eq "113") { $code = "1"; $icon = "sunny" };
		if ($weather eq "116") { $code = "2"; $icon = "partlycloudy" };
		if ($weather eq "119") { $code = "4"; $icon = "cloudy" };
		if ($weather eq "122") { $code = "4"; $icon = "cloudy" };
		if ($weather eq "143") { $code = "6"; $icon = "fog" };
		if ($weather eq "176") { $code = "10"; $icon = "rain" };
		if ($weather eq "179") { $code = "18"; $icon = "sleet" };
		if ($weather eq "182") { $code = "18"; $icon = "sleet" };
		if ($weather eq "185") { $code = "18"; $icon = "sleet" };
		if ($weather eq "200") { $code = "15"; $icon = "tstorms" };
		if ($weather eq "227") { $code = "21"; $icon = "snow" };
		if ($weather eq "230") { $code = "21"; $icon = "snow" };
		if ($weather eq "248") { $code = "6"; $icon = "fog" };
		if ($weather eq "260") { $code = "6"; $icon = "fog" };
		if ($weather eq "263") { $code = "10"; $icon = "rain" };
		if ($weather eq "266") { $code = "12"; $icon = "rain" };
		if ($weather eq "281") { $code = "19"; $icon = "sleet" };
		if ($weather eq "284") { $code = "19"; $icon = "sleet" };
		if ($weather eq "293") { $code = "12"; $icon = "rain" };
		if ($weather eq "296") { $code = "12"; $icon = "rain" };
		if ($weather eq "299") { $code = "13"; $icon = "rain" };
		if ($weather eq "302") { $code = "13"; $icon = "rain" };
		if ($weather eq "305") { $code = "13"; $icon = "rain" };
		if ($weather eq "308") { $code = "13"; $icon = "rain" };
		if ($weather eq "311") { $code = "19"; $icon = "sleet" };
		if ($weather eq "314") { $code = "19"; $icon = "sleet" };
		if ($weather eq "317") { $code = "19"; $icon = "sleet" };
		if ($weather eq "320") { $code = "20"; $icon = "snow" };
		if ($weather eq "323") { $code = "20"; $icon = "sleet" };
		if ($weather eq "326") { $code = "20"; $icon = "sleet" };
		if ($weather eq "329") { $code = "21"; $icon = "snow" };
		if ($weather eq "332") { $code = "21"; $icon = "snow" };
		if ($weather eq "335") { $code = "21"; $icon = "snow" };
		if ($weather eq "338") { $code = "21"; $icon = "snow" };
		if ($weather eq "350") { $code = "18"; $icon = "sleet" };
		if ($weather eq "353") { $code = "12"; $icon = "rain" };
		if ($weather eq "356") { $code = "13"; $icon = "rain" };
		if ($weather eq "359") { $code = "13"; $icon = "rain" };
		if ($weather eq "362") { $code = "18"; $icon = "sleet" };
		if ($weather eq "365") { $code = "18"; $icon = "sleet" };
		if ($weather eq "368") { $code = "20"; $icon = "sleet" };
		if ($weather eq "371") { $code = "21"; $icon = "sleet" };
		if ($weather eq "374") { $code = "18"; $icon = "sleet" };
		if ($weather eq "377") { $code = "18"; $icon = "sleet" };
		if ($weather eq "386") { $code = "15"; $icon = "tstorms" };
		if ($weather eq "389") { $code = "15"; $icon = "tstorms" };
		if ($weather eq "392") { $code = "15"; $icon = "tstorms" };
		if ($weather eq "395") { $code = "16"; $icon = "sleet" };
		if (!$icon) { $icon = "clear" };
		if (!$code) { $code = "1" };
		$newline = $newline . "$code" . "|";
		$newline = $newline . "$icon" . "|";
		$newline = $newline . "$weatherdes" . "|";
		$newline = $newline . "-9999" . "|";
		$newline = $newline . "-9999" . "|";
		$newline = $newline . sprintf("%.1f", $viss->linear($ep)) . "|";
		# Save new line / dataset
		print F "$i|$ep|";
		$t = Time::Piece->new ($ep);
		print F sprintf("%02d", $t->mday) . "|";
		print F sprintf("%02d", $t->mon) . "|";
		my @month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		@month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		print F $t->year . "|";
		print F sprintf("%02d", $t->hour) . "|";
		print F sprintf("%02d", $t->min) . "|";
		my @days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		@days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		print F "$newline\n";
		$i++;
	}
	# Fill data to have at least 72h of forecast data for the weather emulator - otherwise Loxone app
	# scrambles the webdata... :-(
	$i--;
	while ($i < 75) { # Use 75 datasets just to be sure...
		$i++;
		$ep += 3600;
		print F "$i|$ep|";
		$t = Time::Piece->new ($ep);
		print F sprintf("%02d", $t->mday) . "|";
		print F sprintf("%02d", $t->mon) . "|";
		my @month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		@month = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_MONTH_SH'}) );
		$t->mon_list(@month);
		print F $t->monname . "|";
		print F $t->year . "|";
		print F sprintf("%02d", $t->hour) . "|";
		print F sprintf("%02d", $t->min) . "|";
		my @days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		@days = split(' ', Encode::decode("UTF-8", $L{'GRABBER.LABEL_DAYS_SH'}) );
		$t->day_list(@days);
		print F $t->wdayname . "|";
		print F "$newline\n";
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

} # end hourly

# Clean Up Databases

if ( $current ) {

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

if ( $daily ) {

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

if ( $hourly ) {

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
