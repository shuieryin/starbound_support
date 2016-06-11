%%%-------------------------------------------------------------------
%%% @author shuieryin
%%% @copyright (C) 2016, Shuieryin
%%% @doc
%%%
%%% @end
%%% Created : 29. May 2016 3:52 PM
%%%-------------------------------------------------------------------
-module(starbound_common_server).
-author("shuieryin").

-behaviour(gen_server).

%% API
-export([
    start_link/1,
    start/1,
    stop/0,
    get/1,
    all_configs/0,
    all_server_users/0,
    add_user/2,
    user/1,
    all_users/0,
    online_users/0,
    send_message/0
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

-type add_user_status() :: ok | user_exist.

-record(player_info, {
    player_name :: binary(),
    ip_addr :: inet:ip4_address(),
    last_login_time :: erlang:timestamp(),
    agree_restart = false :: boolean()
}).

-record(user_info, {
    username :: binary(),
    last_login_time :: erlang:timestamp(),
    player_infos :: #{PlayerName :: binary() => #player_info{}},
    is_banned = false :: boolean()
}).

-record(state, {
    user_info_path :: file:filename(),
    sbboot_config_path :: file:filename(),
    sbboot_config :: map(),
    online_users = #{} :: #{Username :: binary() => #player_info{}},
    all_users = #{} :: #{Username :: binary() => #user_info{}},
    sb_socket :: gen_tcp:socket()
}).

-record(sb_message, {
    time :: binary(),
    type :: 'Info' | 'Warning' | 'Error' | 'Debug',
    server :: binary(),
    content :: binary()
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
-spec start_link(SbbConfigPath :: file:filename()) -> gen:start_ret().
start_link(SbbConfigPath) ->
    gen_server:start_link({global, ?SERVER}, ?MODULE, SbbConfigPath, []).

%%--------------------------------------------------------------------
%% @doc
%% Starts server by setting module name as server name without link.
%%
%% @end
%%--------------------------------------------------------------------
-spec start(SbbConfigPath :: file:filename()) -> gen:start_ret().
start(SbbConfigPath) ->
    gen_server:start({global, ?SERVER}, ?MODULE, SbbConfigPath, []).

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
-spec all_server_users() -> map().
all_server_users() ->
    gen_server:call({global, ?SERVER}, all_server_users).

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
-spec user(Username) -> Password when
    Username :: binary(),
    Password :: binary().
user(Username) ->
    gen_server:call({global, ?SERVER}, {user, Username}).

%%--------------------------------------------------------------------
%% @doc
%% Get all users info.
%%
%% @end
%%--------------------------------------------------------------------
-spec all_users() -> map().
all_users() ->
    gen_server:call({global, ?SERVER}, all_users).

%%--------------------------------------------------------------------
%% @doc
%% Get online users info.
%%
%% @end
%%--------------------------------------------------------------------
-spec online_users() -> map().
online_users() ->
    gen_server:call({global, ?SERVER}, online_users).

%%--------------------------------------------------------------------
%% @doc
%% Send message to starbound server.
%%
%% @end
%%--------------------------------------------------------------------
-spec send_message() -> ok.
send_message() ->
    gen_server:cast({global, ?SERVER}, send_message).

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
-spec init(SbbConfigPath :: file:filename()) ->
    {ok, State} |
    {ok, State, timeout() | hibernate} |
    {stop, Reason} |
    ignore when

    State :: #state{},
    Reason :: term(). % generic term
init(SbbConfigPath) ->
    io:format("~p starting...", [?MODULE]),
    {ok, RawSbbootConfig} = file:read_file(SbbConfigPath),
    SbbootConfig = json:from_binary(RawSbbootConfig),
    io:format("started~n"),

    ServerHomePath = "/home/steam/steamcmd/starbound/giraffe_storage",
    LogPath = filename:join([ServerHomePath, "starbound_server.log"]),
    UsersInfoPath = filename:join([ServerHomePath, "users_info"]),

    AllUsers =
        case filelib:is_regular(UsersInfoPath) of
            true ->
                {ok, [Term]} = file:consult(UsersInfoPath),
                Term;
            false ->
                #{}
        end,

    spawn(
        fun() ->
            elib:cmd("tail -fn0 " ++ LogPath, fun analyze_log/1)
        end),

    {ok, SbSocket} = gen_udp:open(21025),

    {ok, #state{
        user_info_path = UsersInfoPath,
        sbboot_config = SbbootConfig,
        sbboot_config_path = SbbConfigPath,
        all_users = AllUsers,
        sb_socket = SbSocket
    }}.

%%--------------------------------------------------------------------
%% @doc
%% Analyze starbound log.
%%
%% @end
%%--------------------------------------------------------------------
-spec analyze_log(LineBin :: binary()) -> ok.
analyze_log(LineBin) ->
    case re:run(LineBin, <<"^\\[(\\d{2}:\\d{2}:\\d{2}\\.\\d{3})\\]\s+(\\S*):\\s+(\\S*):\\s+(.*)">>, [{capture, all_but_first, binary}]) of
        {match, [Time, Type, Server, Content]} ->
            gen_server:cast({global, ?SERVER}, {analyze_log, #sb_message{
                time = Time,
                type = binary_to_atom(Type, utf8),
                server = Server,
                content = Content
            }});
        _NoMatch ->
            ok
    end.

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
    all_server_users |
    all_users |
    online_users |
    {add_user, Username, Password} |
    {user, Username},

    Reply :: add_user_status() | term() | Users | undefined,

    Key :: binary(),
    Username :: binary(),
    Password :: binary(),
    Users :: map(),

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
handle_call(all_server_users, _From, State) ->
    {reply, serverUsers(State), State};
handle_call({add_user, Username, Password}, _From, State) ->
    #state{
        sbboot_config = SbbConfig,
        sbboot_config_path = SbbConfigPath
    } = UpdatedState = add_user(Username, Password, State),

    SbbConfigBin = json:to_binary(SbbConfig),
    file:write_file(SbbConfigPath, SbbConfigBin),

    error_logger:info_msg("Added username:[~p], password:[~p]", [Username, Password]),

    {reply, ok, UpdatedState};
handle_call({user, Username}, _From, State) ->
    AllUsers = serverUsers(State),
    Result = case maps:get(Username, AllUsers, undefined) of
                 undefined ->
                     undefined;
                 #{<<"password">> := Password} ->
                     Password
             end,
    {reply, Result, State};
handle_call(all_users, _From, #state{all_users = AllUsers} = State) ->
    {reply, AllUsers, State};
handle_call(online_users, _From, #state{online_users = OnlineUsers} = State) ->
    {reply, OnlineUsers, State}.

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

    Request :: {analyze_log, #sb_message{}} | send_message | stop, % generic term

    State :: #state{},
    NewState :: State,
    Reason :: term(). % generic term
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast({analyze_log, #sb_message{content = Content}}, State) ->
    UpdatedState = handle_login(Content, State),
    UpdatedState1 = handle_logout(Content, UpdatedState),
    {noreply, UpdatedState1};
handle_cast(send_message, #state{sb_socket = SbSocket} = State) ->
    io:format("SbSocket:~p~n", [SbSocket]),
    gen_udp:send(SbSocket, elib:hexstr_to_bin("3804c067305a0c01dfff7f27080d3233333333333333333333333309010a0a426c6162626572696e670f06831508010c010000")),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |¢
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

%%--------------------------------------------------------------------
%% @doc
%% Handle login
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_login(Content :: binary(), #state{}) -> #state{}.
handle_login(Content, #state{
    user_info_path = UsersInfoPath,
    online_users = OnlineUsers,
    all_users = AllUsers
} = State) ->
    case re:run(Content, <<"^Logged\\sin\\saccount\\s''(\\S*)''\\sas\\splayer\\s'(\\S*)'\\sfrom\\saddress\\s(0000:0000:0000:0000:0000:ffff:\\S{4}:\\S{4})">>, [{capture, all_but_first, binary}]) of
        {match, [Username, PlayerName, PlayerAddr]} ->
            Timestamp = os:timestamp(),
            {ok, Ipv4Addr} = elib:ipv6_2_ipv4(PlayerAddr),

            CurPlayerInfo = #player_info{
                player_name = PlayerName,
                ip_addr = Ipv4Addr,
                last_login_time = Timestamp
            },

            UpdatedAllUsers =
                case maps:get(Username, AllUsers, undefined) of
                    undefined ->
                        AllUsers#{
                            Username => #user_info{
                                username = Username,
                                last_login_time = Timestamp,
                                player_infos = #{PlayerName => CurPlayerInfo}
                            }
                        };
                    #user_info{
                        player_infos = PlayerInfos
                    } = ExistingUser ->
                        AllUsers#{
                            Username := ExistingUser#user_info{
                                last_login_time = Timestamp,
                                player_infos = PlayerInfos#{PlayerName => CurPlayerInfo}
                            }
                        }
                end,

            UpdatedOnlineUsers = OnlineUsers#{
                Username => CurPlayerInfo
            },

            spawn(
                fun() ->
                    UpdatedAllUsersBin = io_lib:format("~tp.", [UpdatedAllUsers]),
                    file:write_file(UsersInfoPath, UpdatedAllUsersBin)
                end),

            State#state{
                all_users = UpdatedAllUsers,
                online_users = UpdatedOnlineUsers
            };
        nomatch ->
            State
    end.

%%--------------------------------------------------------------------
%% @doc
%% Handle logout
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_logout(Content :: binary(), #state{}) -> #state{}.
handle_logout(Content, #state{
    online_users = OnlineUsers
} = State) ->
    case re:run(Content, <<"^Client\\s'(\\S*)'\\s<(\\d*)>\\s\\((\\S*\\))\\sdisconnected">>, [{capture, all_but_first, binary}]) of
        {match, [PlayerName, _ServerLoginCount, _PlayerAddr]} ->
            LogoutUsername = maps:fold(
                fun(Username, #player_info{player_name = CurPlayerName}, AccUsername) ->
                    if
                        PlayerName == CurPlayerName ->
                            Username;
                        true ->
                            AccUsername
                    end
                end, undefined, OnlineUsers),

            State#state{
                online_users = maps:remove(LogoutUsername, OnlineUsers)
            };
        nomatch ->
            State
    end.