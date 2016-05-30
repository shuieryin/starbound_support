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
-export([start_link/1]).

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
-spec start_link(SbbConfigPath :: file:filename()) -> supervisor:startlink_ret().
start_link(SbbConfigPath) ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, SbbConfigPath).

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
-spec init(SbbConfigPath :: file:filename()) ->
    {ok, {SupFlags :: supervisor:sup_flags(), [ChildSpec :: supervisor:child_spec()]}} | ignore.
init(SbbConfigPath) ->
    [{_AppName, _AppVersion, _Applications, _ReleaseStatus}] = release_handler:which_releases(permanent),
    erlang:set_cookie(node(), wechat_mud),

    RestartStrategy = one_for_one,
    MaxRestarts = 1000,
    MaxSecondsBetweenRestarts = 3600,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    {ok, {
        SupFlags,
        [
            {common_server,
                {common_server, start_link, [SbbConfigPath]},
                permanent,
                10000,
                worker,
                [common_server]
            }
        ]
    }}.