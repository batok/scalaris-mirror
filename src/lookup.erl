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
%%% File    : lookup.erl
%%% Author  : Thorsten Schuett <schuett@zib.de>
%%% Description : lookup algorithm
%%%
%%% Created :  3 May 2007 by Thorsten Schuett <schuett@zib.de>
%%%-------------------------------------------------------------------
%% @author Thorsten Schuett <schuett@zib.de>
%% @copyright 2007-2008 Konrad-Zuse-Zentrum für Informationstechnik Berlin
%% @version $Id$
-module(lookup).

-author('schuett@zib.de').
-vsn('$Id$ ').

-include("chordsharp.hrl").

-export([lookup_aux/4, lookup_fin/2, get_key/4, set_key/5]).

%logging on
%-define(LOG(S, L), io:format(S, L)).
%logging off
-define(LOG(S, L), ok).

lookup_fin(_Hops, Msg) ->
    %io:format("Hops: ~p~n", [Hops]),
    self() ! Msg.
    
lookup_aux(State, Key, Hops, Msg) ->
    Terminate = util:is_between(cs_state:id(State), Key, cs_state:succ_id(State)),
    P = ?RT:next_hop(State, Key),
    ?LOG("[ ~w | I | Node   | ~w ] lookup_aux ~w ~w ~s~n",[calendar:universal_time(), self(), Terminate, P, Key]),
    if
	Terminate ->
	    cs_send:send(P, {lookup_fin, Hops + 1, Msg});
	true ->
	    cs_send:send(P, {lookup_aux, Key, Hops + 1, Msg})
    end.

get_key(State, Source_PID, HashedKey, Key) ->
    ?LOG("[ ~w | I | Node   | ~w ] get_key ~s~n",[calendar:universal_time(), self(), Key]),
    cs_send:send(Source_PID, {get_key_response, Key, ?DB:read(cs_state:get_db(State), HashedKey)}).

set_key(State, Source_PID, Key, Value, Versionnr) ->
    ?LOG("[ ~w | I | Node   | ~w ] set_key ~s ~s~n",[calendar:universal_time(), self(), Key, Value]),
    cs_send:send(Source_PID, {set_key_response, Key, Value, Versionnr}),
    DB = ?DB:write(cs_state:get_db(State), Key, Value, Versionnr),
    cs_state:set_db(State, DB).
