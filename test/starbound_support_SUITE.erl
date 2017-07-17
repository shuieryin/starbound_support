%%%-------------------------------------------------------------------
%%% @author shuieryin
%%% @copyright (C) 2015, Shuieryin
%%% @doc
%%%
%%% @end
%%% Created : 24. Nov 2015 7:42 PM
%%%-------------------------------------------------------------------
-module(starbound_support_SUITE).
-author("shuieryin").

%% API
-export([
    all/0,
    init_per_suite/1,
    end_per_suite/1,
    init_per_group/2,
    end_per_group/2,
    init_per_testcase/2,
    end_per_testcase/2,
    groups/0,
    suite/0
]).

-export([
    starbound_common_server_test/1
]).

-include_lib("common_test/include/ct.hrl").

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Comment starts here
%%
%% @end
%%--------------------------------------------------------------------
suite() ->
    [].

all() ->
    [
        {group, servers}
    ].

groups() ->
    [{
        servers,
        [{repeat, 1}], % parallel
        [
            starbound_common_server_test
        ]
    }].

starbound_common_server_test(Cfg) -> starbound_common_server_test:test(Cfg).

%%%===================================================================
%%% Init states
%%%===================================================================
init_per_suite(Config) ->
    error_logger:tty(false),
    {data_dir, RawDataDir} = lists:keyfind(data_dir, 1, Config),
    DataDir = filename:dirname(filename:dirname(RawDataDir)),
    DummySbbConfigPath = filename:join([DataDir, "starbound_server.config"]),
    starbound_common_server:start(DummySbbConfigPath, starbound_support),
    Config.

end_per_suite(_Config) ->
    starbound_common_server:stop(),
    ok.

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, _Config) ->
    ok.

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.