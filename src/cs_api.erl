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
%%% File    : cs_api.erl
%%% Author  : Thorsten Schuett <schuett@zib.de>
%%% Description : Chord# API
%%%
%%% Created : 16 Apr 2007 by Thorsten Schuett <schuett@zib.de>
%%%-------------------------------------------------------------------
%% @author Thorsten Schuett <schuett@zib.de>
%% @copyright 2007-2008 Konrad-Zuse-Zentrum für Informationstechnik Berlin
%% @version $Id$
-module(cs_api).

-author('schuett@zib.de').
-vsn('$Id$ ').

-export([read/1, write/2, test_and_set/3]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Public Interface
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @type key() = term(). Key
%% @type value() = term(). Value

%% @doc reads the value of a key
%% @spec read(key()) -> {failure, term()} | value()
read(Key) ->
    case transstore.transaction_api:quorum_read(Key) of
	{fail, Reason} ->
	    {fail, Reason};
	{Value, _Version} ->
	    Value
    end.
	    

%% @doc writes the value of a key
%% @spec write(key(), value()) -> ok | {fail, term()}
write(Key, Value) ->
    case transstore.transaction_api:single_write(Key, Value) of
	commit ->
	    ok;
	{fail, Reason} ->
	    {fail, Reason}
    end.

%% @doc atomic compare and swap
%% @spec test_and_set(key(), value(), value()) -> {fail, Reason} | ok
test_and_set(Key, OldValue, NewValue) ->
    TFun = fun(TransLog) ->
                   {Result, TransLog1} = transstore.transaction_api:read(Key, TransLog),
                   case Result of
                       {value, ReadValue} ->
                           if
                               ReadValue == OldValue ->
                                   {Result2, TransLog2} = transstore.transaction_api:write(Key, NewValue, TransLog1),
                                   if
                                       Result2 == ok ->
                                           {{ok, done}, TransLog2};
                                       true ->
                                           {{fail, notfound}, TransLog2}
                                   end;
                               true ->
                                   {{fail, {key_changed, ReadValue}}, TransLog1}
                           end;
                       {fail, not_found} ->
                           {Result2, TransLog2} = transstore.transaction_api:write(Key, NewValue, TransLog),
                           if
                               Result2 == ok ->
                                   {{ok, done}, TransLog2};
                               true ->
                                   {{fail, write}, TransLog2}
                           end
                       end
           end,
    SuccessFun = fun(X) -> {success, X} end,
    FailureFun = fun(X) -> {failure, X} end,
    case do_transaction_locally(TFun, SuccessFun, FailureFun, 5000) of
	{trans, {success, {commit, done}}} ->
	    ok;
	{trans, {failure, Reason}} ->
	    {fail, Reason};
	X ->
	    io:format("X: ~p~n", [X]),
	    X
    end.


% I know there is a cs_node in this instance so I will use it directly
%@private
do_transaction_locally(TransFun, SuccessFun, Failure, Timeout) ->
    {ok, PID} = process_dictionary:find_cs_node(),
    PID ! {do_transaction, TransFun, SuccessFun, Failure, cs_send:this()},
    receive
	X ->
	    X
    after
	Timeout ->
	   do_transaction_locally(TransFun, SuccessFun, Failure, Timeout)
    end.
