%%%-------------------------------------------------------------------
%%% @author shuieryin
%%% @copyright (C) 2016, Shuieryin
%%% @doc
%%%
%%% @end
%%% Created : 29. May 2016 3:52 PM
%%%-------------------------------------------------------------------
-module(common_server).
-author("shuieryin").

-behaviour(gen_server).

%% API
-export([
    start_link/0,
    start/0,
    stop/0,
    get/1,
    all_configs/0,
    all_users/0,
    add_user/2,
    get_user/1
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3,
    format_status/2
]).

-define(SERVER, ?MODULE).
-define(SBBCONFIG_PATH, "/Users/shuieryin/Workspaces/starbound_support/sbboot.config").

-type add_user_status() :: ok | user_exist.

-record(state, {
    sbboot_config :: map()
}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> gen:start_ret().
start_link() ->
    gen_server:start_link({global, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc
%% Starts server by setting module name as server name without link.
%%
%% @end
%%--------------------------------------------------------------------
-spec start() -> gen:start_ret().
start() ->
    gen_server:start({global, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc
%% Stop server.
%%
%% @end
%%--------------------------------------------------------------------
-spec stop() -> ok.
stop() ->
    gen_server:cast(?SERVER, stop).

%%--------------------------------------------------------------------
%% @doc
%% Get value by given key.
%%
%% @end
%%--------------------------------------------------------------------
-spec get(binary()) -> term().
get(Key) ->
    gen_server:call({global, ?SERVER}, {get, Key}).

%%--------------------------------------------------------------------
%% @doc
%% Get value by given key.
%%
%% @end
%%--------------------------------------------------------------------
-spec all_configs() -> map().
all_configs() ->
    gen_server:call({global, ?SERVER}, all_configs).

%%--------------------------------------------------------------------
%% @doc
%% Get all users.
%%
%% @end
%%--------------------------------------------------------------------
-spec all_users() -> map().
all_users() ->
    gen_server:call({global, ?SERVER}, all_users).

%%--------------------------------------------------------------------
%% @doc
%% Add username and password.
%%
%% @end
%%--------------------------------------------------------------------
-spec add_user(Username, Password) -> ok when
    Username :: binary(),
    Password :: binary().
add_user(Username, Password) ->
    gen_server:call({global, ?SERVER}, {add_user, Username, Password}).

%%--------------------------------------------------------------------
%% @doc
%% Add username and password.
%%
%% @end
%%--------------------------------------------------------------------
-spec get_user(Username) -> Password when
    Username :: binary(),
    Password :: binary().
get_user(Username) ->
    gen_server:call({global, ?SERVER}, {get_user, Username}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec init(Args) ->
    {ok, State} |
    {ok, State, timeout() | hibernate} |
    {stop, Reason} |
    ignore when

    Args :: term(),
    State :: #state{},
    Reason :: term(). % generic term
init([]) ->
    io:format("~p starting...", [?MODULE]),
    {ok, RawSbbootConfig} = file:read_file(?SBBCONFIG_PATH),
    SbbootConfig = json:from_binary(RawSbbootConfig),
    io:format("started~n"),
    {ok, #state{
        sbboot_config = SbbootConfig
    }}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_call(Request, From, State) ->
    {reply, Reply, NewState} |
    {reply, Reply, NewState, timeout() | hibernate} |
    {noreply, NewState} |
    {noreply, NewState, timeout() | hibernate} |
    {stop, Reason, Reply, NewState} |
    {stop, Reason, NewState} when

    Request :: {get, Key} |
    all_configs |
    all_users |
    {add_user, Username, Password} |
    {get_user, Username},

    Reply :: add_user_status() | term() | undefined,

    Key :: binary(),
    Username :: binary(),
    Password :: binary(),

    From :: {pid(), Tag :: term()}, % generic term
    State :: #state{},
    NewState :: State,
    Reason :: term(). % generic term
handle_call({get, Key}, _From, #state{
    sbboot_config = SbbConfig
} = State) ->
    {reply, maps:get(Key, SbbConfig, undefined), State};
handle_call(all_configs, _From, #state{
    sbboot_config = SbbConfig
} = State) ->
    {reply, SbbConfig, State};
handle_call(all_users, _From, State) ->
    {reply, serverUsers(State), State};
handle_call({add_user, Username, Password}, _From, State) ->
    AllUsers = serverUsers(State),
    {Status, UpdatedState} =
        case maps:is_key(Username, AllUsers) of
            true ->
                {user_exist, State};
            false ->
                #state{
                    sbboot_config = SbbConfig
                } = State2 = add_user(Username, Password, State),

                SbbConfigBin = json:to_binary(SbbConfig),
                file:write_file(?SBBCONFIG_PATH, SbbConfigBin),

                {ok, State2}
        end,
    {reply, Status, UpdatedState};
handle_call({get_user, Username}, _From, State) ->
    AllUsers = serverUsers(State),
    Result = case maps:get(Username, AllUsers, undefined) of
                 undefined ->
                     undefined;
                 #{<<"password">> := Password} ->
                     Password
             end,
    {reply, Result, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Request, State) ->
    {noreply, NewState} |
    {noreply, NewState, timeout() | hibernate} |
    {stop, Reason, NewState} when

    Request :: term() | stop, % generic term
    State :: #state{},
    NewState :: State,
    Reason :: term(). % generic term
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(_Request, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec handle_info(Info | timeout(), State) ->
    {noreply, NewState} |
    {noreply, NewState, timeout() | hibernate} |
    {stop, Reason, NewState} when

    Info :: term(), % generic term
    State :: #state{},
    NewState :: State,
    Reason :: term(). % generic term
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec terminate(Reason, State) -> ok when
    Reason :: (normal | shutdown | {shutdown, term()} | term()), % generic term
    State :: #state{}.
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn, State, Extra) ->
    {ok, NewState} |
    {error, Reason} when

    OldVsn :: term() | {down, term()}, % generic term
    State :: #state{},
    Extra :: term(), % generic term
    NewState :: State,
    Reason :: term(). % generic term
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is useful for customising the form and
%% appearance of the gen_server status for these cases.
%%
%% @spec format_status(Opt, StatusData) -> Status
%% @end
%%--------------------------------------------------------------------
-spec format_status(Opt, StatusData) -> Status when
    Opt :: 'normal' | 'terminate',
    StatusData :: [PDict | State],
    PDict :: [{Key :: term(), Value :: term()}], % generic term
    State :: #state{},
    Status :: term(). % generic term
format_status(Opt, StatusData) ->
    gen_server:format_status(Opt, StatusData).

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Get all server users.
%%
%% @end
%%--------------------------------------------------------------------
-spec serverUsers(#state{}) -> map().
serverUsers(#state{
    sbboot_config = SbbConfig
}) ->
    DefaultConfig = maps:get(<<"defaultConfiguration">>, SbbConfig),
    maps:get(<<"serverUsers">>, DefaultConfig).

%%--------------------------------------------------------------------
%% @doc
%% Add user
%%
%% @end
%%--------------------------------------------------------------------
-spec add_user(Username, Password, #state{}) -> #state{} when
    Username :: binary(),
    Password :: binary().
add_user(Username, Password, #state{
    sbboot_config = #{
        <<"defaultConfiguration">> := #{
            <<"serverUsers">> := ExistingServerUsers
        } = DefaultConfig
    } = SbbConfig
} = State) ->
    State#state{
        sbboot_config = SbbConfig#{
            <<"defaultConfiguration">> := DefaultConfig#{
                <<"serverUsers">> := ExistingServerUsers#{
                    Username => #{
                        <<"admin">> => false,
                        <<"password">> => Password
                    }
                }
            }
        }
    }.