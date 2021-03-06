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
%%% File    : tparticipant.erl
%%% Author  : Monika Moser <moser@zib.de>
%%% Description : transaction algorithm related to a participant
%%%               unlike for the transaction manager there won't be 
%%%                   a separate thread for each participant
%%%                   
%%%
%%% Created :  11 Feb 2008 by Monika Moser <moser@zib.de>
%%%-------------------------------------------------------------------
%% @author Monika Moser <moser@zib.de>
%% @copyright 2007-2008 Konrad-Zuse-Zentrum für Informationstechnik Berlin
%% @version $Id$

-module(transstore.tparticipant).

-author('moser@zib.de').
-vsn('$Id$ ').

-include("trecords.hrl").
-include("../chordsharp.hrl").

-export([tp_validate/3, tp_commit/2, tp_abort/2]).

-import(?DB).
-import(gb_trees).
-import(lists).
-import(io).
-import(cs_send).
-import(cs_state).



%% TP method:
%%     validate operation on a certain item
%%     only committed items can be read
-spec(tp_validate/3 :: (any(), any(), any()) -> any()).
tp_validate(State, Tid, Item)->
    %?TLOGN("validating item ~p", [Item]),
    %% Check whether the version is still valid
    {DB, LockRes} = case ?DB:read(cs_state:get_db(State), Item#item.rkey) of
			 {ok, _Value, Version} ->
			     set_lock(cs_state:get_db(State), check_version(Item, Version), Item);
			 _Any ->
			     case Item#item.operation of
				 write ->
				     set_lock(cs_state:get_db(State), success, Item);
				 _Any2 ->
				     {cs_state:get_db(State), failed}
			     end    
		     end,
    Decision = decision(LockRes),
    NewState = update_transaction_participant_log(cs_state:set_db(State, DB), Tid, Item, Decision),
    NewVote = trecords:new_vote(Tid, Item#item.key, Item#item.rkey, Decision, 1),   
    tsend:send_vote_to_rtms(Item#item.tms, NewVote),
    NewState.
    

-spec(set_lock/3 :: (any(), success | fail, any()) -> {any(), ok | failed}).
set_lock(DB, success, #item{operation=read} = Item) ->
    ?DB:set_read_lock(DB, Item#item.rkey);
set_lock(DB, success, #item{operation=write} = Item) ->
    ?DB:set_write_lock(DB, Item#item.rkey);
set_lock(DB, _LockFailed, _Item)->
    {DB, failed}.

decision(ok)->
    prepared;
decision(_)->
    abort.

update_transaction_participant_log(State, Tid, Item, prepared) ->
    update_state(State, Tid, tp_log:new_logentry(prepared, Tid, Item));
update_transaction_participant_log(State, Tid, Item, abort) ->
    update_state(State, Tid, tp_log:new_logentry(local_abort, Tid, Item)).

update_state(OldState, Tid, LogEntry)->
    tp_log:add_to_undecided(OldState, Tid, LogEntry).
    
check_version(#item{operation=read} = TransactionItem, Version)-> 
     if
	 TransactionItem#item.version >= Version ->   
	     success;
	 true ->
	     fail
     end;
check_version(#item{operation=write} = TransactionItem, Version)-> 
    if
	TransactionItem#item.version == (Version + 1) ->
	    success;
	true ->
	    fail
    end.

tp_commit(State, TransactionID)->
    %?TLOGN("committing transaction ~p", [TransactionID]),
    TransLog = tp_log:get_log(State),
    TransLogUndecided = TransLog#translog.undecided, 
    case gb_trees:is_defined(TransactionID, TransLogUndecided) of
	true ->
	    LogEntries = gb_trees:get(TransactionID, TransLogUndecided),
	    DB = tp_commit_store_unlock(cs_state:get_db(State), LogEntries),
	    State2 = cs_state:set_db(State, DB),
	    NewTransLog = tp_log:get_log(State2),
	    tp_log:remove_from_undecided(State2, TransactionID, NewTransLog, TransLogUndecided);
	_Any ->
	    %%get information about transaction --- might have missed something before
	    State
    end.

tp_commit_store_unlock(DB, []) ->
    DB;
tp_commit_store_unlock(DB, [Entry | LogRest])->
    {DB3, _} = case Entry#logentry.operation of
	write ->
	    DB2 = ?DB:write(DB, Entry#logentry.rkey, Entry#logentry.value, Entry#logentry.version),
	    %_Stored = ?DB:read(Entry#logentry.rkey),
	    ?DB:unset_write_lock(DB2, Entry#logentry.rkey);
	_Any ->
	    ?DB:unset_read_lock(DB, Entry#logentry.rkey)
    end,
    
    tp_commit_store_unlock(DB3, LogRest).

tp_abort(State, TransactionID)->
    ?TLOGN("aborting transaction ~p", [TransactionID]),
    TransLog = tp_log:get_log(State),
    TransLogUndecided = TransLog#translog.undecided,
    case gb_trees:is_defined(TransactionID, TransLogUndecided) of
	true ->
	    LogEntries = gb_trees:get(TransactionID, TransLogUndecided),
	    DB = tp_abort_unlock(cs_state:get_db(State), LogEntries),
	    State2 = cs_state:set_db(State, DB),
	    NewTransLog = tp_log:get_log(State2),
	    tp_log:remove_from_undecided(State2, TransactionID, NewTransLog, TransLogUndecided);
	_Any ->
	    %%get information about transaction --- might have missed something before
	    State
    end.

tp_abort_unlock(DB, []) ->
    DB;	    
tp_abort_unlock(DB, [Entry | LogRest])->
    {DB2, _} = case Entry#logentry.status of
	prepared ->
	    case Entry#logentry.operation of
		write ->
		    ?DB:unset_write_lock(DB, Entry#logentry.rkey);
		read ->
		    ?DB:unset_read_lock(DB, Entry#logentry.rkey)
	    end;
	_Any ->
	    {DB, ok}
    end,
    tp_abort_unlock(DB2, LogRest).    
    
