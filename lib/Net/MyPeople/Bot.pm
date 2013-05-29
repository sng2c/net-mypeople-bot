package Net::MyPeople::Bot;
use 5.010;
use strict;
use warnings;
use Moose;
use Data::Dumper;
use LWP::UserAgent;
use LWP::Protocol::https;
use HTTP::Request::Common;
use JSON;
use Data::Printer;
use URI::Escape;

# ABSTRACT: Implements MyPeople-Bot.

# VERSION

=pod 

=head1 SYNOPSIS

	use Net::MyPeople::Bot;
	use AnyEvent::HTTPD;
	use Data::Dumper;

	my $bot = Net::MyPeople::Bot({apikey=>'MYPEOPLE_BOT_APIKEY'});

	# You should set up callback url with below informations. ex) http://MYSERVER:8080/callback
	my $httpd = AnyEvent::HTTPD->new (port => 8080);
	$httpd->reg_cb (
		'/callback' => sub {
			my ($httpd, $req) = @_;

			my $action = $req->parm('action');
			my $buddyId = $req->parm('buddyId');
			my $groupId = $req->parm('groupId');
			my $content = $req->parm('content');

			callback( $action, $buddyId, $groupId, $content );
		}
	);
	sub callback{
		my ($action, $buddyId, $groupId, $content ) = @_;
		p @_;
		if   ( $action eq 'addBuddy' ){ # when someone add this bot as a buddy.
		
			my $buddy = $bot->buddy($buddyId); # hashref
			my $buddy_name = $buddy->{buddys}->{name};
			my $res = $bot->send($buddyId, "Nice to meet you, $buddy_name");

		}
		elsif( $action eq 'sendFromMessage' ){ # when someone send a message to this bot.
			my @res = $bot->send($buddyId, "$content");
		}
		elsif( $action eq 'createGroup' ){ # when this bot invited to a group chat channel.
		
			my $res = $bot->groupSend($groupId, 'Nice to meet you, guys.');
			# CONTENT
			# [
			# 	{"buddyId":"BU_ey3aPnSCpzx3ccwqidwdfg00","isBot":"Y","name":"testbot","photoId":"myp_pub:51A586C2074DB00010"},
			# 	{"buddyId":"BU_ey3aPnSCpzx3ccwqidwdfg00","isBot":"Y","name":"testbot","photoId":"myp_pub:51A586C2074DB00010"}
			# ]
		
		}
		elsif( $action eq 'inviteToGroup' ){ # when someone in a group chat channel invites user to the channel.
			
			my $buddy_name = $content->[0]->{name};
			my $is_bot = $content->[0]->{is_bot} eq 'Y';
			
			# CONTENT
			# [
			# 	{"buddyId":"BU_ey3aPnSCpzx3ccwqidwdfg00","isBot":"Y","name":"testbot","photoId":"myp_pub:51A586C2074DB00010"}
			# ]
			
			if( $is_bot ){ # bot self
				my $res = $bot->groupSend($groupId, 'Nide to meet you, guys');
			}
		
			else{ # other guy
				my $res = $bot->groupSend($groupId, "$buddy_name, Can you introduce your self?");
			}
		}
		elsif( $action eq 'exitFromGroup' ){ # when someone in a group chat channel leaves.

			my $buddy = $bot->buddy($buddyId); # hashref
			my $buddy_name = $buddy->{buddys}->[0]->{name};
			my $res = $bot->sendGroup($groupId, "I'll miss $buddy_name ...");

		}
		elsif( $action eq 'sendFromGroup'){ # when received from group chat channel
			if( $content eq 'bot.goout' ){ # a reaction for an user defined command, 'bot.goout'
				my $res = $bot->groupSend($groupId, 'Bye~');
				$res = $bot->groupExit($groupId);
			}
			else{
				my $res = $bot->groupSend($groupId, "(GROUP_ECHO) $content");
			}
		}
	}

	$httpd->run;
=cut

has apikey=>(
	is=>'rw'
);

has ua=>(
	is=>'ro',
	default=>sub{return LWP::UserAgent->new;}
);

our $API_BASE = 'https://apis.daum.net/mypeople';
our $API_SEND = $API_BASE . '/buddy/send.json';
our $API_BUDDY = $API_BASE . '/profile/buddy.json';
our $API_GROUP_MEMBERS = $API_BASE . '/group/members.json';
our $API_GROUP_SEND = $API_BASE . '/group/send.json';
our $API_GROUP_EXIT = $API_BASE . '/group/exit.json';
our $API_FILE_DOWNLOAD = $API_BASE . '/file/download.json';

sub BUILD {
	my $self = shift;
}

sub _call_file {
	my $self = shift;
	my ($apiurl, $param, $path) = @_;
	$param->{apikey} = $self->apikey;
	foreach my $k (keys %{$param}){
		$param->{$k} = uri_escape($param->{$k});
	}

	my $req = POST( $apiurl, Content=>$param );
	my $res = $self->ua->request( $req );

	if( $res->is_success ){
		$path =~ s@[\\/]$@@;
		my $filepath;
		if( -d $path ){
			$filepath = $path.'/'.$res->filename;
		}
		else{
			$filepath = $path;
		}
		open my $fh, '<', $filepath;
		binmode($fh);
		print $fh $res->content;
		close $fh;
		return $filepath;
	}
	else{
		return undef;
	}
}
sub _call_multipart {
	my $self = shift;
	my ($apiurl, $param) = @_;
	$param->{apikey} = $self->apikey;
	foreach my $k (keys %{$param}){
		$param->{$k} = uri_escape($param->{$k});
	}

	my $req = POST(	$apiurl, 
		Content_Type => 'form-data',
		Content => $param
		);
#	print $req->as_string;

	my $res = $self->ua->request($req);

	if( $res->is_success ){
		return from_json( $res->content );
	}
	else{
		return undef;
	}
}
sub _call {
	my $self = shift;
	my ($apiurl, $param) = @_;
	$param->{apikey} = $self->apikey;
	foreach my $k (keys %{$param}){
		$param->{$k} = uri_escape($param->{$k});
	}

	my $req = POST( $apiurl, Content=>$param );
	my $res = $self->ua->request( $req );
	
	if( $res->is_success ){
		return from_json( $res->content );
	}
	else{
		return undef, $res;
	}
}

sub buddy{
	my $self = shift;
	my ($buddyId) = @_;
	return $self->_call($API_BUDDY, {buddyId=>$buddyId} );
}

sub groupMembers{
	my $self = shift;
	my ($groupId) = @_;
	return $self->_call($API_GROUP_MEMBERS, {groupId=>$groupId} );
}

sub send{
	my $self = shift;
	my ($buddyId, $content, $attach) = @_;
	if( $attach && -f $attach ){
		return $self->_call_multipart($API_SEND, {buddyId=>$buddyId, attach=>[$attach]} );
	}
	else{
		return $self->_call($API_SEND, {buddyId=>$buddyId, content=>$content} );
	}
}

sub groupSend{
	my $self = shift;
	my ($groupId, $content, $attach) = @_;
	if( $attach && -f $attach ){
		return $self->_call_multipart($API_GROUP_SEND, {groupId=>$groupId, attach=>[$attach]} );
	}
	else{
		return $self->_call($API_GROUP_SEND, {groupId=>$groupId, content=>$content} );
	}
}

sub groupExit{
	my $self = shift;
	my ($groupId) = @_;
	return $self->_call($API_GROUP_EXIT, {groupId=>$groupId} );
}

sub fileDownload{
	my $self = shift;
	my ($fileId, $path) = @_;
	return $self->_call_file($API_FILE_DOWNLOAD, {fileId=>$fileId} , $path);
}


