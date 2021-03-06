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
%%% File    : tp_log.erl
%%% Author  : Monika Moser <moser@zib.de>
%%% Description : operations on the transaction log of a transaction participant 
%%%               functions to extract certain information 
%%% Created :  10 Jul 2007 by Monika Moser <moser@zib.de>
%%%-------------------------------------------------------------------
%% @author Monika Moser <moser@zib.de>
%% @copyright 2007-2008 Konrad-Zuse-Zentrum für Informationstechnik Berlin
%% @version $Id$
-module(transstore.tp_log).

-author('moser@zib.de').
-vsn('$Id$ ').

-include("trecords.hrl").

-export([get_log/1, new_item/6, new_logentry/3, add_to_undecided/3, remove_from_undecided/4]).

-import(cs_state).
-import(gb_trees).
-import(lists).


%%% Structure of the transaction log:
%%% top gb_tree:  key: TransID
%%%               value: Transaction data (transaction record)
%%%       

new_item(Key, RKey, Value, Version, Operation, TransactionManagers) ->
    #item{
	  key = Key,
	  rkey = RKey,
	  value = Value,
	  version = Version,
	  operation = Operation,
	  tms = TransactionManagers
	 }.


new_logentry(Status, TransID, Item)->
    #logentry{
	      status = Status,
	      key = Item#item.key,
	      rkey = Item#item.rkey,
	      value = Item#item.value,
	      version = Item#item.version,
	      operation = Item#item.operation,
	      transactionID = TransID,
	      tms = Item#item.tms
	     }.


get_log(State)->
    cs_state:get_trans_log(State).


add_to_undecided(State, TransID, LogEntry)->
    TransLog = cs_state:get_trans_log(State),
    TransInLog = gb_trees:is_defined(TransID, TransLog#translog.undecided),
    if
	TransInLog == true -> 
	    TransInLogList = gb_trees:get(TransID, TransLog#translog.undecided),
	    NewTransInLogList = lists:append([LogEntry], TransInLogList);
	true ->
	    NewTransInLogList = [LogEntry]
    end,
    
    NewTransInLog = gb_trees:enter(TransID, NewTransInLogList, TransLog#translog.undecided),
    cs_state:set_trans_log(State, TransLog#translog{undecided=NewTransInLog}).   
    
remove_from_undecided(State, TransID, TransLog, TransLogUndecided)->
    NewLogEntries = gb_trees:delete(TransID, TransLogUndecided),
    cs_state:set_trans_log(State, TransLog#translog{undecided=NewLogEntries}).
