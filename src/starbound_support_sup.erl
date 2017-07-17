%%%-------------------------------------------------------------------
%%% @author Shuieryin
%%% @copyright (C) 2015, Shuieryin
%%% @doc
%%%
%%% Starbound support root supervisor.
%%%
%%% @end
%%% Created : 26. Aug 2015 11:04 AM
%%%-------------------------------------------------------------------
-module(starbound_support_sup).

-behaviour(supervisor).

%% API
-export([start_link/2]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the supervisor
%%
%% @end
%%--------------------------------------------------------------------
-spec start_link(SbbConfigPath :: file:filename(), AppName :: atom()) -> supervisor:startlink_ret().
start_link(SbbConfigPath, AppName) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, {SbbConfigPath, AppName}).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a supervisor is started using supervisor:start_link/[2,3],
%% this function is called by the new process to find out about
%% restart strategy, maximum restart frequency and child
%% specifications.
%%
%% @end
%%--------------------------------------------------------------------
-spec init({SbbConfigPath :: file:filename(), AppName :: atom()}) ->
    {ok, {SupFlags :: supervisor:sup_flags(), [ChildSpec :: supervisor:child_spec()]}} | ignore.
init({SbbConfigPath, AppName}) ->
    erlang:set_cookie(node(), wechat_mud),

    InfoServerName = list_to_atom(atom_to_list(AppName) ++ "_information_server"),

    RestartStrategy = one_for_one,
    MaxRestarts = 1000,
    MaxSecondsBetweenRestarts = 3600,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    {ok, {
        SupFlags,
        [
            {starbound_common_server,
                {starbound_common_server, start_link, [SbbConfigPath, AppName]},
                permanent,
                10000,
                worker,
                [starbound_common_server]
            },

            {InfoServerName,
                {information_server, start_link, [InfoServerName]},
                permanent,
                10000,
                worker,
                [InfoServerName]
            }
        ]
    }}.