# NAME

Net::MyPeople::Bot - Implements MyPeople-Bot.

# VERSION

version 0.200

# SYNOPSIS

	#!/usr/bin/env perl 

	use strict;
	use warnings;
	use utf8;

	use Net::MyPeople::Bot;
	use AnyEvent::HTTPD;
	use Data::Printer;
	use JSON;
	use Log::Log4perl qw(:easy);
	Log::Log4perl->easy_init($DEBUG); # you can see requests in Net::MyPeople::Bot.

	my $APIKEY = 'OOOOOOOOOOOOOOOOOOOOOOOOOO'; 
	my $bot = Net::MyPeople::Bot->new({apikey=>$APIKEY});

	# You should set up callback url with below informations. ex) http://MYSERVER:8080/callback
	my $httpd = AnyEvent::HTTPD->new (port => 8080);
	$httpd->reg_cb (
		'/'=> sub{
			my ($httpd, $req) = @_;
			$req->respond( { content => ['text/html','hello'] });
		},
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
			# $buddyId : buddyId who adds this bot to buddys.
			# $groupId : ""
			# $content : buddy info for buddyId 
			# [
			#    {"buddyId":"XXXXXXXXXXXXXXXXXXXX","isBot":"N","name":"XXXX","photoId":"myp_pub:XXXXXX"},
			# ]

			my $buddy = from_json($content)->[0]; # 
			my $buddy_name = $buddy->{buddys}->{name};
			my $res = $bot->send($buddyId, "Nice to meet you, $buddy_name");

		}
		elsif( $action eq 'sendFromMessage' ){ # when someone send a message to this bot.
			# $buddyId : buddyId who sends message
			# $groupId : ""
			# $content : text

			my @res = $bot->send($buddyId, "$content");
			if($content =~ /^myp_pci:/){
				$bot->fileDownload($content,'./sample.jpg');
				# you can also download a profile image with buddy's photoId,'myp_pub:XXXXXXX'
			}
			if($content =~ /sendtest/){
				$bot->send($buddyId,undef,'./sample.jpg');
			}
			if($content =~ /buddytest/){
				my $buddy = $bot->buddy($buddyId);
				#{"buddys":[{"buddyId":"XXXXXXXXXXXXXXX","name":"XXXX","photoId":"myp_pub:XXXXXXXXXXXXXXX"}],"code":"200","message":"Success"}
				$bot->send($buddyId, to_json($buddy));
			}
		}
		elsif( $action eq 'createGroup' ){ # when this bot invited to a group chat channel.
			# $buddyId : buddyId who creates
			# $groupId : new group id
			# $content : members
			# [
			#    {"buddyId":"XXXXXXXXXXXXXXXXXXXX","isBot":"N","name":"XXXX","photoId":"myp_pub:XXXXXX"},
			#    {"buddyId":"XXXXXXXXXXXXXXXXXXXX","isBot":"N","name":"XXXX","photoId":"myp_pub:XXXXXX"},
			#    {"buddyId":"XXXXXXXXXXXXXXXXXXXX","isBot":"Y","name":"XXXX","photoId":"myp_pub:XXXXXX"}
			# ]

			my $members = from_json($content);
			my @names;
			foreach my $member (@{$members}){
				next if $member->{isBot} eq 'Y';# bot : The group must have only one bot. so, isBot='Y' means bot itself.
				push(@names, $member->{name});
			}

			my $res = $bot->groupSend($groupId, (join(',',@names)).'!! Nice to meet you.');
		

		}
		elsif( $action eq 'inviteToGroup' ){ # when someone in a group chat channel invites user to the channel.
			# $buddyId : buddyId who invites member
			# $groupId : group id where new member is invited
			# $content : 
			# [
			#    {"buddyId":"XXXXXXXXXXXXXXXXXXXX","isBot":"N","name":"XXXX","photoId":"myp_pub:XXXXXX"},
			#    {"buddyId":"XXXXXXXXXXXXXXXXXXXX","isBot":"Y","name":"XXXX","photoId":"myp_pub:XXXXXX"}
			# ]
			my $invited = from_json($content);
			my @names;
			foreach my $member (@{$invited}){
				next if $member->{isBot} eq 'Y';
				push(@names, $member->{name});
			}
			my $res = $bot->groupSend($groupId, (join(',',@names))."!! Can you introduce your self?");

		}
		elsif( $action eq 'exitFromGroup' ){ # when someone in a group chat channel leaves.
			# $buddyId : buddyId who exits
			# $groupId : group id where member exits
			# $content : ""

			my $buddy = $bot->buddy($buddyId); # hashref
			my $buddy_name = $buddy->{buddys}->[0]->{name};
			my $res = $bot->sendGroup($groupId, "I'll miss $buddy_name ...");

		}
		elsif( $action eq 'sendFromGroup'){ # when received from group chat channel
			# $buddyId : buddyId who sends message
			# $groupId : group id where message is sent
			# $content : text

			if( $content eq 'bot.goout' ){ # a reaction for an user defined command, 'bot.goout'
				my $res = $bot->groupSend($groupId, 'Bye~');
				$res = $bot->groupExit($groupId);
			}
			elsif($content =~ /membertest/){
				my $members= $bot->groupMembers($groupId);
				$bot->groupSend($groupId, to_json($members));
			}
			else{

				my $res = $bot->groupSend($groupId, "(GROUP_ECHO) $content");
			}
		}
	}
	print "Bot is started\n";
	$httpd->run;

# Description

MyPeople is an instant messenger service of Daum Communications in Republic of Korea (South Korea).

MyPeople Bot is API interface of MyPeople.

If you want to use this bot API, 
Unfortunately,you must have an account for http://www.daum.net.
And you can understand Korean.

- $res = $self->buddy( BUDDY\_ID )

    get infomations of a buddy.

    returns buddy info.

    	{
    		"buddys":
    			[
    				{
    					"buddyId":"XXXXXXXXXXXXXXX",
    					"name":"XXXX",
    					"photoId":
    					"myp_pub:XXXXXXXXXXXXXXX"
    				}
    			],
    			"code":"200",
    			"message":"Success"
    	}

- $res = $self->groupMembers( GROUP\_ID )

    Get members in a group.

    returns infos of members in the GROUP.

    	{
    		"buddys":
    			[
    				{
    					"buddyId":"XXXXXXXXXXXXXXX",
    					"name":"XXXX",
    					"photoId":
    					"myp_pub:XXXXXXXXXXXXXXX"
    				},
    				{
    					"buddyId":"XXXXXXXXXXXXXXX",
    					"name":"XXXX",
    					"photoId":
    					"myp_pub:XXXXXXXXXXXXXXX"
    				},

    				...
    			],
    			"code":"200",
    			"message":"Success"
    	}

- $res = $self->send( BUDDY\_ID, TEXT )
- $res = $self->send( BUDDY\_ID, undef, FILEPATH )

    send text to a buddy.

    If you set FILEPATH, it sends the file to the buddy.

    returns result of request.

- $res = $self->groupSend( GROUP\_ID, TEXT )
- $res = $self->groupSend( GROUP\_ID, undef, FILEPATH )

    send text to a group.

    If you set FILEPATH, it sends the file to the group.

    returns result of request.

- $res = $self->groupExit( GROUP\_ID )

    exit from a group.

    returns result of request.

- $res = $self->fileDownload( FILE\_ID, DIRPATH\_OR\_FILEPATH )

    download attached file with FILE\_ID.

    If you set directory path on second argument, the file is named automatically by 'Content-Disposition' header.

    returns path of the file saved.

## Callbacks

See SYNOPSIS.

# See Also

- MyPeople : [https://mypeople.daum.net/mypeople/web/main.do](https://mypeople.daum.net/mypeople/web/main.do)
- MyPeople Bot API Home : [http://dna.daum.net/apis/mypeople](http://dna.daum.net/apis/mypeople)

# AUTHOR

khs <sng2nara@gmail.com>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by khs.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
