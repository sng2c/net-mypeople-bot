package Net::MyPeople::Bot;
use 5.010;
use utf8;
use Moose;
use namespace::autoclean;
use Data::Dumper;
use LWP::UserAgent;
use LWP::Protocol::https;
use HTTP::Request::Common;
use JSON;
use Data::Printer;
use URI::Escape;
use Log::Log4perl qw(:easy);
use File::Util qw(SL);
use Encode;
Log::Log4perl->easy_init($ERROR);

# ABSTRACT: Implements MyPeople-Bot.

# VERSION

=pod 

=head1 SYNOPSIS

	use Net::MyPeople::Bot;
	use AnyEvent::HTTPD;
	use Data::Dumper;

	my $bot = Net::MyPeople::Bot({apikey=>'MYPEOPLE_BOT_APIKEY'});
	# You can get MYPEOPLE_BOT_APIKEY at http://dna.daum.net/myapi/authapi/mypeople

	# You should set up CALLBACK URL with below informations. ex) http://MYSERVER:8080/callback
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
		if   ( $action eq 'addBuddy' ){ # when someone add this bot as a buddy.
		
			my $buddy = $bot->buddy($buddyId); # hashref
			my $buddy_name = $buddy->{buddys}->{name};
			my $res = $bot->send($buddyId, "Nice to meet you, $buddy_name");

		}
		elsif( $action eq 'sendFromMessage' ){ # when someone send a message to this bot.

			if($content =~ /^myp_pci:/){
				$bot->fileDownload($content,'./sample.jpg');
			}
			elsif($content =~ /sendtest/){
				$bot->send($buddyId,undef,'./sample.jpg');
			}
			else{
				my @res = $bot->send($buddyId, "$content");
			}

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

=head1 Description

MyPeople is an instant messenger service of Daum Communications in Republic of Korea (South Korea).

MyPeople Bot is API interface of MyPeople.

If you want to use this bot API, 
Unfortunately,you must have an account for http://www.daum.net.
And you can understand Korean.

Other details will be updated soon. Sorry :-)

=head1 See Also

=item *

MyPeople : L<https://mypeople.daum.net/mypeople/web/main.do>

=item *

MyPeople Bot API Home : L<http://dna.daum.net/apis/mypeople>

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
	$apiurl .= '?apikey='.uri_escape($self->apikey);

	foreach my $k (keys %{$param}){
		$param->{$k} = uri_escape($param->{$k});
	}

	my $req = POST( $apiurl, Content=>$param );
	DEBUG $req->as_string;
	my $res = $self->ua->request( $req );

	if( $res->is_success ){
		my $sl = SL;
		$path =~ s@$sl$@@;
		my $filepath;
		if( -d $path ){
			$filepath = $path.SL.$res->filename;
		}
		else{
			$filepath = $path;
		}
		DEBUG $filepath;
		open my $fh, '>', $filepath;
		binmode($fh);
		print $fh $res->content;
		close $fh;
		return $filepath;
	}
	else{
		return undef,$res;
	}
}
sub _call_multipart {
	my $self = shift;
	my ($apiurl, $param) = @_;
	$apiurl .= '?apikey='.$self->apikey;

	#foreach my $k (keys %{$param}){
	#	$param->{$k} = uri_escape($param->{$k});
	#}

	my $req = POST(	$apiurl, 
		Content_Type => 'form-data',
		Content => $param
		);
	DEBUG $req->as_string;

	my $res = $self->ua->request($req);
	DEBUG p $res;

	if( $res->is_success ){
		return from_json( $res->content );
	}
	else{
		return undef, $res;
	}
}
sub _call {
	my $self = shift;
	my ($apiurl, $param) = @_;
	$apiurl .= '?apikey='.uri_escape($self->apikey);

	foreach my $k (keys %{$param}){
		my $v = $param->{$k};
		#$v = Encode::encode('UTF-8',$v);
		$param->{$k} = uri_escape($v);
	}

	my $req = POST( $apiurl, 
		#Content_Type => 'form-data',
		Content=>$param 
	);
	DEBUG $req->as_string;
	my $res = $self->ua->request( $req );
	DEBUG p $res;
	
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
	my ($buddyId, $content, $attach_path) = @_;
	if( $attach_path && -f $attach_path ){
		return $self->_call_multipart($API_SEND, [buddyId=>$buddyId, attach=>[$attach_path]] );
	}
	else{
		return $self->_call($API_SEND, {buddyId=>$buddyId, content=>$content} );
	}
}

sub groupSend{
	my $self = shift;
	my ($groupId, $content, $attach_path) = @_;
	if( $attach_path && -f $attach_path ){
		return $self->_call_multipart($API_GROUP_SEND, [groupId=>$groupId, attach=>[$attach_path]] );
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


__PACKAGE__->meta->make_immutable;
1;
