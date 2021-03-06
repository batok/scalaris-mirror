%  Copyright 2007-2008 Konrad-Zuse-Zentrum für Informationstechnik Berlin
%
%   Licensed under the Apache License, Version 2.0 (the "License");
%   you may not use this file except in compliance with the License.
%   You may obtain a copy of the License at
%
%       http://www.apache.org/licenses/LICENSE-2.0
%
%   Unless required by applicable law or agreed to in writing, software
%   distributed under the License is distributed on an "AS IS" BASIS,
%   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%   See the License for the specific language governing permissions and
%   limitations under the License.
%%%-------------------------------------------------------------------
%%% File    : tmanager.erl
%%% Author  : Monika Moser <moser@zib.de>
%%% Description : the manager or replicated manager for a transaction
%%% Created :  11 Feb 2007 by Monika Moser <moser@zib.de>
%%%-------------------------------------------------------------------
%% @author Monika Moser <moser@zib.de>
%% @copyright 2007-2008 Konrad-Zuse-Zentrum für Informationstechnik Berlin
%% @version $Id$
%% @doc 
-module(transstore.tmanager).

-author('moser@zib.de').
-vsn('$Id$').

-include("trecords.hrl").

-import(cs_send).
-import(ct).
-import(lists).
-import(erlang).
-import(timer).
-import(lists).
-import(dict).
-import(io_lib).
-import(io).
-import(config).
-import(cs_symm_replication).
-import(boot_logger).

-export([start_manager/6, start_manager_commit/6, start_replicated_manager/6]).

%% for timer module
-export([read_phase/1, init_phase/1, start_commit/1]).

%%==============================================================================
%% Information on the algorithms:
%%
%% 1) Ballot Numbers of the Paxos Protocol:
%%    * Each TP votes with the Ballot Number 1
%%    * Each initial leader gets Ballot Number 2 
%%    * Replicated Transaction Managers get Ballot numbers > 2
%% 
%%    Ballot numbers reflect the order of replicated transaction 
%%      mangers. When the leader fails the next rTM takes over 
%%      after the interval of (Ballot-2)*config:leaderDetectorInterval().
%%      rTMs do not really elect a leader, rather they behave like a 
%%      leader after a certain amount of time. This is reasonable as 
%%      the commit phase should not take longer than some seconds.
%%
%% 
%%
%%
%%
%% TODO: 
%%      RTMS send outcome to Owner in case the leader fails
%%      add unique references to messages on the outcome of a transaction
%%          in case two managers send the outcome, one message should be dropped 
%%      Store outcome for TPs that did not receive a decision
%%==============================================================================



%% start a manager: it will execute the readphase and commit phase
start_manager(TransFun, SuccessFun, FailureFun, Owner, TID, InstanceId)->
    erlang:put(instance_id, InstanceId),
    {TimeRP, {Res, ResVal}} = timer:tc(transstore.tmanager, read_phase, [TransFun]),
    if
	Res == ok ->
	    {ReadPVal, Items} = ResVal,
	    commit_phase(Items, SuccessFun, ReadPVal, FailureFun, Owner, TID, TimeRP);
	Res == fail->
	    tsend:send_to_client(Owner, FailureFun(ResVal));
	Res == abort ->
	    tsend:send_to_client(Owner, SuccessFun({user_abort, ResVal}));
	true ->
	    io:format("readphase res: ~p ; resval: ~p~n", [Res, ResVal]),
	    tsend:send_to_client(Owner, FailureFun(Res))
    end.

%% start a manager without a read phase
start_manager_commit(Items, SuccessFun, FailureFun, Owner, TID, InstanceId)->
    erlang:put(instance_id, InstanceId),
    commit_phase(Items, SuccessFun, empty ,FailureFun, Owner, TID, 0).

%% readphase: execute the transaction function
%% it can fail, due to an indication in the TFun given by the user
%% or when operations on items fail, not catched by the user in the TFun
read_phase(TFun)->
    TLog = transstore.trecords:new_translog(),
    {{TFunFlag, ReadVal}, TLog2} = try 
				       TFun(TLog)
				       catch {abort, State} ->
					   State
				   end,
					       
    %?TLOGN("TLOG in readphase ~p~n", [TLog2]),
    if
	TFunFlag == ok ->
	     FailedItems = lists:filter(fun({_,_, ItemResult, _, _}) ->
					       if
						   ItemResult == fail ->
						       true;
						   true ->
						       false
					       end
					end, 
					TLog2),
	    NumFailedItems = length(FailedItems),
	    if
		NumFailedItems > 0 ->
		    {fail, fail};
		true ->
		    {ok, {ReadVal, trecords:create_items(TLog2)}}
	    end;  
	true -> %%TFunFlag == abort/fail ReadVal not_found, timeout, fail
	    {TFunFlag, ReadVal}
    end.

%% commit phase
commit_phase(Items, SuccessFun, ReadPhaseResult, FailureFun, Owner, TID, _TimeRP)->
    %% BEGIN only for time measurements	    
    _ItemsListLength = length(dict:to_list(Items)),
    %boot_logger:transaction_log(io_lib:format("| ~p | | | | | | ~p ", [TID, _ItemsListLength])),
    %% END only for time measurements
    TMState1 = init_leader_state(TID, Items),
    {_TimeIP, {InitRes, TMState2}} = timer:tc(transstore.tmanager, init_phase, [TMState1]),
    %?TLOGN("init phase: initres ~p", [InitRes]),
    if
	InitRes == ok->
	    erlang:send_after(config:tpFailureTimeout(), self(), {check_failed_tps}),
	    {_TimeCP, TransRes} = timer:tc(transstore.tmanager, start_commit, [TMState2]),
	    ?TIMELOG("commit phase", _TimeCP/1000),
	    %?TLOGN("Result of transaction: ~p", [TransRes]),
	    if
		TransRes == commit->
		    %boot_logger:transaction_log(io_lib:format("| ~p | ~f | ~f |~f | commit | ~p", [TID, TimeRP/1000, TimeIP/1000, TimeCP/1000, ItemsListLength])),
		    tsend:send_to_client(Owner, SuccessFun({commit, ReadPhaseResult}));
		true ->
		    %boot_logger:transaction_log(io_lib:format("| ~p | ~f | ~f |~f | abort | ~p", [TID, TimeRP/1000, TimeIP/1000, TimeCP/1000, ItemsListLength])),
		    tsend:send_to_client(Owner, FailureFun(abort))
	    end;
	true ->
	    ?TLOGN("Init Phase Failed ~p", [InitRes]),
	    tsend:send_to_client(Owner, FailureFun(abort))
    end.

init_leader_state(TID, Items)->
    {SelfKey, _TS} = TID,
    LeaderBallot = 2,
    TMState = trecords:new_tm_state(TID, Items, cs_send:this(), {SelfKey, cs_send:this(), LeaderBallot}),
    TMState#tm_state{myBallot=LeaderBallot}.


%% Init Phase, lookup all transaction participants and replicated managers
init_phase(TMState)->
    TMMessage = {init_rtm, trecords:new_tm_message(TMState#tm_state.transID, {cs_send:this(), TMState#tm_state.items})},
    tsend:send_to_rtms_with_lookup(TMState#tm_state.transID, TMMessage),
    
    TPMessage = {lookup_tp, #tp_message{item_key = unknown, message={cs_send:this()}}},
    tsend:send_to_participants_with_lookup(TMState, TPMessage),
    erlang:send_after(config:transactionLookupTimeout(), self(), {rtm_lookup_timeout}),
    
    receive_lookup_rtms_tps_repl(TMState).

receive_lookup_rtms_tps_repl(TMState)->
    receive
	{rtm_lookup_timeout} ->
	    NumRTMs = length(TMState#tm_state.rtms),
	    Limit = config:quorumFactor(),
	    EnoughTPs = check_tps(TMState, Limit),
	    if
		(NumRTMs >= Limit) and EnoughTPs->
		    %?TLOGN("Found RTMs ~p~n, TPs for items: ~p ~n", [TMState#tm_state.rtms, TMState#tm_state.items]),
		    {ok, TMState};
		true ->
		    ?TLOGN("Found not enough RTMs and TPs~n", []),
		    tsend:send_to_rtms(TMState, {kill}),
		    {timeout, TMState}
	    end;
	{rtm, Address, RKey}->
	    %?TLOGN("rtm for key ~p at ~p", [RKey, node(Address)]),
	    NumRTMs = length(TMState#tm_state.rtms) + 1,
	    Ballot = NumRTMs + 1,
	    TMState2 = TMState#tm_state{rtms = [{RKey, Address, Ballot} | TMState#tm_state.rtms]},
	    Limit = (config:replicationFactor()),
	    if
		NumRTMs == Limit->
		    TMState3 = TMState2#tm_state{rtms_found = true},
		    if
			TMState3#tm_state.tps_found == true ->
			    %?TLOGN("Found RTMs ~p~n, TPs for items: ~p ~n", [TMState#tm_state.rtms, TMState#tm_state.items]),
			    {ok, TMState3};
			true ->
			    receive_lookup_rtms_tps_repl(TMState3)
		    end;
		true ->
		    receive_lookup_rtms_tps_repl(TMState2)
	    end;
	{tp, ItemKey, OrigKey, Address} ->
	    %?TLOGN("tp for key ~p at ~p ", [ItemKey, node(Address)]),
	    TMState2 = add_tp(TMState, ItemKey, OrigKey, Address),
	    Limit = config:replicationFactor(),
	    AllTPs = check_tps(TMState2, Limit),
	    if
		AllTPs == true ->
		    TMState3 = TMState2#tm_state{tps_found = true},
		    if
			TMState3#tm_state.rtms_found == true->
			    %?TLOGN("Found RTMs ~p~n, TPs for items: ~p ~n", [TMState#tm_state.rtms, TMState#tm_state.items]),
			    {ok, TMState3};
			true ->
			    receive_lookup_rtms_tps_repl(TMState3)
		    end;
		true ->
		    receive_lookup_rtms_tps_repl(TMState2)
	    end
    
    end.

%% ad a tp to the TMState
add_tp(TMState, ItemKey, OriginalKey, Address) ->
    %OriginalKey = cs_symm_replication:get_original_key(ItemKey),
    Item = dict:fetch(OriginalKey, TMState#tm_state.items),
    TPs = Item#tm_item.tps,
    NewTPs = [{ItemKey, Address} | TPs],
    NewItem = Item#tm_item{tps = NewTPs},
    TMState#tm_state{items = dict:store(OriginalKey, NewItem, TMState#tm_state.items)}.

%% check whether we have enough TPs for all items
check_tps(TMState, Limit) ->
    Keys = dict:fetch_keys(TMState#tm_state.items),
    lists:all(fun(Item)-> 
		      ItemValues = dict:fetch(Item, TMState#tm_state.items), 
		      TPs = ItemValues#tm_item.tps,
		      if
			  length(TPs) >= Limit ->
			      true;
					   true ->
			      false
		      end end, Keys).


start_commit(TMState)->
    tsend:tell_rtms(TMState),
    dict:map(fun(_Key, Item)-> 
		     tsend:send_prepare_item(TMState, Item) end, 
	     TMState#tm_state.items),
    loop(TMState).

start_replicated_manager(TransID, Items, Leader, RKey, InstanceId, Owner)->
    Owner ! {the_pid, cs_send:this()},
    erlang:put(instance_id, InstanceId),
    if
	Leader == true ->
	    NLeader = cs_send:this();
	true ->
	    NLeader = Leader
    end,
    TMState = trecords:new_tm_state(TransID, Items, NLeader, {RKey, cs_send:this(), unknownballot}),
    loop(TMState).


loop(TMState)->
    receive
	{kill}->
	    %% Init Phase at the leader must have failed
	    ?TLOGN("Got killed, an init phase must have failed", []),
	    abort;
	{vote,_Sender, Vote} ->
	    %?TLOGN("received vote ~p", [Vote]),
	    TMState2 = tmanager_pac:process_vote(TMState, Vote),
	    loop(TMState2);
	{vote_ack, Key, RKey, VoteDecision, Timestamp} ->
	    %?TLOGN("received ack ~p", [RKey]),
	    TMState2 = tmanager_pac:process_vote_ack(TMState, Key, RKey, VoteDecision, Timestamp),
	    loop(TMState2);
	{read_vote, Vote}->
	    %?TLOGN("received read vote ~p", [Vote]),
	    TMState2 = tmanager_pac:process_read_vote(TMState, Vote),
	    loop(TMState2);
	{read_vote_ack, Key, RKey, Timestamp, StoredVote}->
	    %?TLOGN("received read_vote_ack ~p", [RKey]),
	    TMState2 = tmanager_pac:collect_rv_ack(TMState, Key, RKey, Timestamp, StoredVote),
	    loop(TMState2);
	{rtms, RTMs, MyBallot} ->
	    %?TLOGN("received rtms ~p", [RTMs]),
	    TMState2 = TMState#tm_state{rtms = RTMs, myBallot = MyBallot},
	    %% simple leader election
	    if
		MyBallot > 2 -> %% not the leader
		    erlang:send_after(time_become_leader(MyBallot), self(), {become_leader}),
		    loop(TMState2);
		true->
		    loop(TMState2)
	    end;
	{check_failed_tps} ->
	    %?TLOGN("received check_failed_tps", []),
	    %io:format("checking failed tps ~n", []),
	    check_failed_tps(TMState),
	    %%loop(TMState),
	    abort;
	{decision, Decision} ->
	    %?TLOGN("received decision ~p", [Decision]),
	    Decision;
	{rtm, Address, _RKey}->
	    %late arrival of a RTM: kill it, it has nothing to do
	    tsend:send(Address, {kill}),
	    loop(TMState);
	{become_leader}->
	    ?TLOGN("I'm becoming a leader", []),
	    tmanager_pac:vote_for_suspected(TMState),
	    NewBal = TMState#tm_state.myBallot + config:replicationFactor(), 
	    erlang:send_after(time_become_leader(NewBal), self(), {become_leader}),
	    loop(TMState#tm_state{myBallot = NewBal});
	_ ->
	    %io:format("TManager got unknown message ~p~n", [X]),
	    %?TLOGN("unknown message ~p", [X]),
	    loop(TMState)
    after config:tmanagerTimeout()->
	    if
		length(TMState#tm_state.rtms) == 1->
		    ?TLOGN("Tmanager Timeout: in init phase", []),
		    %loop(TMState);
		    ?TLOGN("Kill myself, an init phase must have failed", []),
		    abort;
		true ->
		    ?TLOGN("Tmanager Timeout: after init phase", []),
		    loop(TMState)
		    %io:format("this should not happen! there is a transaction that did not get a decision~n", [])
		    %loop(TMState)
	    end
    end.


%%--------------------------------------------------------------------
%% Function: check_failed_tps/1 
%% Purpose:  check for which tps we have no decision for, start a read
%%               phase for the suspected TPs
%% Args: TMState - the state of the TM
%%--------------------------------------------------------------------

check_failed_tps(TMState)->
    %Vote abort for all TPs that seem to have failed
    tmanager_pac:vote_for_suspected(TMState),
    TMState.

time_become_leader(MyBallot)->
    (MyBallot - 2) * config:leaderDetectorInterval().
