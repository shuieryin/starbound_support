%%%-------------------------------------------------------------------
%%% @author shuieryin
%%% @copyright (C) 2015, Shuieryin
%%% @doc
%%%
%%% @end
%%% Created : 29. Nov 2015 8:09 PM
%%%-------------------------------------------------------------------
-module(starbound_common_server_test).
-author("shuieryin").

%% API
-export([
    test/1
]).

-define(SERVER, player_fsm).

-include_lib("starbound_support_test.hrl").

-record(state, {
    all_server_users :: map(),
    test_times :: pos_integer()
}).

%%%===================================================================
%%% API
%%%===================================================================

test(_Config) ->
    ModelState = #state{
        all_server_users = starbound_common_server:all_server_users(),
        test_times = 600
    },

    RandomFuncs = [
        fun user/1,
        fun all_configs/1,
        fun get/1,
        fun add_user/1
    ],

    run_test(RandomFuncs, ModelState).

run_test(RandomFuncs, #state{test_times = TestTimes} = ModelState) ->
    lists:foreach(
        fun(_Index) ->
            apply(?ONE_OF(RandomFuncs), [ModelState])
        end, lists:seq(1, TestTimes)),
    true.

%%%===================================================================
%%% Internal functions
%%%===================================================================
user(#state{
    all_server_users = AllUsers
}) ->
    Username = ?ONE_OF([<<"undefined_user">> | maps:keys(AllUsers)]),
    starbound_common_server:user(Username).

all_configs(_State) ->
    starbound_common_server:all_configs().

get(_State) ->
    starbound_common_server:get(?ONE_OF([<<"defaultConfiguration">>, <<"sjkdlfj">>])).

add_user(_State) ->
    starbound_common_server:add_user(<<"test_user2">>, <<"test_user2_password">>).