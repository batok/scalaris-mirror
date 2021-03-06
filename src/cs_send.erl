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
%%% File    : cs_send.erl
%%% Author  : Thorsten Schuett <schuett@zib.de>
%%% Description : Message Sending. This module allows to configure 
%%%           Scalaris for using Distributed Erlang or TCP for inter-node
%%%           communication.
%%%
%%% Created :  15 May 2007 by Thorsten Schuett <schuett@zib.de>
%%%-------------------------------------------------------------------
%% @author Thorsten Schuett <schuett@zib.de>
%% @copyright 2007-2008 Konrad-Zuse-Zentrum für Informationstechnik Berlin
%% @version $Id$
-module(cs_send).

-author('schuett@zib.de').
-vsn('$Id$ ').

-include("transstore/trecords.hrl").

-export([send/2, this/0, get/2]).

-define(TCP_LAYER, true). % TCP communication
%-define(BUILTIN, true).   % distributed Erlang native communication

-ifdef(TCP_LAYER).
-type(mypid() :: {inet:ip_address(), integer(), pid()}).

-spec(this/0 :: () -> mypid()).
this() ->
    %self().
    comm_layer.comm_layer:this().

-spec(send/2 :: (mypid(), any()) -> ok).
send(Pid, Message) ->
    %Pid ! Message.
    comm_layer.comm_layer:send(Pid, Message).

% get process Name on node Node
get(Name, {IP, Port, _Pid}=_Node) ->
    {IP, Port, Name}.

-endif.

-ifdef(BUILTIN).
-type(mypid() :: pid()).
this() ->
    self().

send(Pid, Message) ->
    Pid ! Message.

get(Name, {_Pid,Host}) ->
    {Name, Host};
get(Name, Pid) ->
    {Name, node(Pid)}.

-endif.
