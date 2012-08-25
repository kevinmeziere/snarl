-module(snarl_user).
-include("snarl.hrl").
-include_lib("riak_core/include/riak_core_vnode.hrl").

-export([
         ping/0,
	 list/0,
	 auth/2,
	 get/1,
	 add/1,
	 delete/1,
	 passwd/2,
	 join/2,
	 leave/2,
	 grant/2,
	 revoke/2,
	 allowed/2
        ]).

-define(TIMEOUT, 5000).

%% Public API

%% @doc Pings a random vnode to make sure communication is functional
ping() ->
    DocIdx = riak_core_util:chash_key({<<"ping">>, term_to_binary(now())}),
    PrefList = riak_core_apl:get_primary_apl(DocIdx, 1, snarl_user),
    [{IndexNode, _Type}] = PrefList,
    riak_core_vnode_master:sync_spawn_command(IndexNode, ping, snarl_user_vnode_master).

auth(User, Passwd) ->
    {ok, ReqID} = snarl_user_read_fsm:get(User),
    case wait_for_reqid(ReqID, ?TIMEOUT) of
	{ok, not_found} ->
	    not_found;
	{ok, UserObj} ->
	    CurrentHash = UserObj#user.passwd,
	    case crypto:sha([User, Passwd]) of
		CurrentHash ->
		    true;
		_ ->
		    false
	    end
	end.

allowed(User, Permission) ->
    {ok, ReqID} = snarl_user_read_fsm:get(User),
    case wait_for_reqid(ReqID, ?TIMEOUT) of
	{ok, not_found} ->
	    not_found;
	{ok, UserObj} ->
	    test_user(UserObj, Permission)
	end.

get(User) ->
    {ok, ReqID} = snarl_user_read_fsm:get(User),
    wait_for_reqid(ReqID, ?TIMEOUT).

list() ->
    {ok, ReqID} = snarl_user_read_fsm:list(),
    wait_for_reqid(ReqID, ?TIMEOUT).

add(User) ->
    do_write(User, add).

passwd(User, Passwd) ->
    do_write(User, passwd, Passwd).

join(User, Group) ->
    do_write(User, join, Group).

leave(User, Group) ->
    do_write(User, leave, Group).

delete(User) ->
    do_write(User, delete).

grant(User, Permission) ->
    do_write(User, grant, Permission).

revoke(User, Permission) ->
    do_write(User, revoke, Permission).



%%%===================================================================
%%% Internal Functions
%%%===================================================================
do_write(User, Op) ->
    {ok, ReqID} = snarl_user_write_fsm:write(User, Op),
    wait_for_reqid(ReqID, ?TIMEOUT).

do_write(User, Op, Val) ->
    {ok, ReqID} = snarl_user_write_fsm:write(User, Op, Val),
    wait_for_reqid(ReqID, ?TIMEOUT).

wait_for_reqid(ReqID, Timeout) ->
    ?PRINT({waiting_for, ReqID}),
    receive
	{ReqID, ok} -> 
	    ok;
        {ReqID, ok, Val} -> 
	    {ok, Val};
	Other -> 
	    ?PRINT({yuck, Other})
    after Timeout ->
	    {error, timeout}
    end.



match([], []) ->
    lager:info("snarl:match - Direct match"),
    true;

match(P, ['...']) ->
    lager:info("snarl:match - Matched ~p by '...'", [P]),
    true;

match([], ['...'|_Rest]) ->
    false;

match([], [_X|_R]) ->
    false;

match([X | InRest], ['...', X|TestRest] = Test) ->
    match(InRest, TestRest) orelse match(InRest, Test);

match([_,X|InRest], ['...', X|TestRest] = Test) ->
    match(InRest, TestRest) orelse match([X| InRest], Test);

match([X|InRest], [X|TestRest]) ->
    match(InRest, TestRest);

match([_|InRest], ['_'|TestRest]) ->
    match(InRest, TestRest);

match(_, _) ->
    false.

test_perms(_Perm, []) ->
    false;

test_perms(Perm, [Test|Tests]) ->
    match(Perm, Test) orelse test_perms(Perm, Tests).

test_groups(_Permission, []) ->
    false;

test_groups(Permission, [Group|Groups]) ->
    case snarl_group:get(Group) of
	{ok, GroupObj} ->
	    case test_perms(Permission, GroupObj#group.permissions) of
		true ->
		    true;
		false ->
		    test_groups(Permission, Groups)
	    end;
	_ ->
	    test_groups(Permission, Groups)
    end.

test_user(UserObj, Permission) ->
    case test_perms(Permission, UserObj#user.permissions) of
	true ->
	    true;
	false ->
	    test_groups(Permission, UserObj#user.groups)
    end.
