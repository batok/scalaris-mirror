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
%%% File    : rt_loop.erl
%%% Author  : Thorsten Schuett <schuett@zib.de>
%%% Description : routing table process
%%%
%%% Created :  5 Dec 2008 by Thorsten Schuett <schuett@zib.de>
%%%-------------------------------------------------------------------
%% @author Thorsten Schuett <schuett@zib.de>
%% @copyright 2008 Konrad-Zuse-Zentrum für Informationstechnik Berlin
%% @version $Id$
-module(rt_loop).

-author('schuett@zib.de').
-vsn('$Id$ ').

% for routing table implementation
-export([start_link/1, start/2]).

-export([dump/0]).

-include("chordsharp.hrl").

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Routing Table maintenance process
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc spawns a routing table maintenance process
%% @spec start_link(term()) -> {ok, pid()}
start_link(InstanceId) ->
    Link = spawn_link(?MODULE, start, [InstanceId, self()]),
    receive
        start_done ->
            ok
    end,
    {ok, Link}.

start(InstanceId, Sup) ->
    process_dictionary:register_process(InstanceId, routing_table, self()),
    io:format("[ I | RT     | ~p ] starting ringtable~n", [self()]),
    timer:send_interval(config:pointerStabilizationInterval(), self(), {stabilize}),
    Sup ! start_done,
    loop().

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Private Code
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
loop() ->
    receive
	{init, Id, Pred, Succ} ->
	    loop(Id, Pred, Succ, ?RT:empty(Succ))
    end.

loop(Id, Pred, Succ, RTState) ->
    receive
	% can happen after load-balancing
	{init, Id, NewPred, NewSucc} ->
	    check(RTState, ?RT:empty(NewSucc)),
	    loop(Id, NewPred, NewSucc, ?RT:empty(NewSucc));
	% regular stabilize operation
	{stabilize} ->
	    Pid = process_dictionary:lookup_process(erlang:get(instance_id), cs_node),
	    Pid ! {get_pred_succ, cs_send:this()},
	    NewRTState = ?RT:stabilize(Id, Succ, RTState),
	    failuredetector2:remove_subscriber(self()),
	    failuredetector2:subscribe(?RT:to_pid_list(RTState)),
	    check(RTState, NewRTState),
	    loop(Id, Pred, Succ, NewRTState);
	% got new successor
	{get_pred_succ_response, NewPred, NewSucc} ->
	    loop(Id, NewPred, NewSucc, RTState);
	{rt_get_node_response, Index, Node} ->
	    NewRTState = ?RT:stabilize(Id, Succ, RTState, Index, Node),
	    check(RTState, NewRTState),
	    loop(Id, Pred, Succ, NewRTState);
	{lookup_pointer_response, Index, Node} ->
	    NewRTState = ?RT:stabilize_pointer(Id, RTState, Index, Node),
	    check(RTState, NewRTState),
	    loop(Id, Pred, Succ, NewRTState);
	{'$gen_cast', {debug_info, Requestor}} ->
	    Requestor ! {debug_info_response, [{"rt_debug", ?RT:dump(RTState)}, {"rt_size", ?RT:get_size(RTState)}]},
	    loop(Id, Pred, Succ, RTState);
	{crash, DeadPid} ->
	    loop(Id, Pred, Succ, ?RT:filterDeadNode(RTState, DeadPid));
	{dump} ->
	    io:format("~p:~p~n", [Id, ?RT:dump(RTState)]),
	    loop(Id, Pred, Succ, RTState);
	X ->
	    io:format("@rt_loop: unknown message ~p ~n", [X]),
	    loop(Id, Pred, Succ, RTState)
    end.
 

check(X, X) ->
    ok;
check(_OldRT, NewRT) ->
    Pid = process_dictionary:lookup_process(erlang:get(instance_id), cs_node),
    Pid ! {rt_update, NewRT}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Debug
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dump() ->
    Pids = process_dictionary:find_all_processes(routing_table),
    [Pid ! {dump} || Pid <- Pids],
    ok.
