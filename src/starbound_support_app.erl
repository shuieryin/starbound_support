%%%-------------------------------------------------------------------
%%% @author Shuieryin
%%% @copyright (C) 2015, Shuieryin
%%% @doc
%%%
%%% Staround support application start.
%%%
%%% @end
%%% Created : 26. Aug 2015 11:04 AM
%%%-------------------------------------------------------------------
-module(starbound_support_app).

-behaviour(application).

%% Application callbacks
-export([
    start/2,
    stop/1
]).

-record(state, {}).

%% ===================================================================
%% Application callbacks
%% ===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Start application
%%
%% @end
%%--------------------------------------------------------------------
-spec start(StartType, StartArgs) -> Return when
    StartType :: application:start_type(),
    StartArgs :: term(), % generic term
    Return :: {ok, pid(), State :: #state{}}.
start(normal, _StartArgs) ->
    {ok, Pid} = starbound_support_sup:start_link(),
    {ok, Pid, #state{}}.

%%--------------------------------------------------------------------
%% @doc
%% Stop application
%%
%% @end
%%--------------------------------------------------------------------
-spec stop(State) -> ok when
    State :: #state{}.
stop(_State) ->
    ok.