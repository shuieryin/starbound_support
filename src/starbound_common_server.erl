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
    ban_user/2,
    unban_user/1,
    user/1,
    all_users/0,
    online_users/0,
    restart_sb/0,
    safe_restart_sb/0,
    pending_usernames/0,
    server_status/0
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
-define(ANALYZE_PROCESS_NAME, read_sb_log).

-type add_user_status() :: ok | user_exist.
-type safe_restart_status() :: done | pending.
-type ban_reason() :: simultaneously_duplicated_login | undefined.

-record(player_info, {
    player_name :: binary(),
    ip_addr :: inet:ip4_address(),
    last_login_time :: erlang:timestamp(),
    agree_restart = false :: boolean()
}).

-record(user_info, {
    username :: binary(),
    password :: binary(),
    last_login_time :: erlang:timestamp() | undefined,
    player_infos = #{} :: #{PlayerName :: binary() => #player_info{}},
    ban_reason :: ban_reason()
}).

-record(state, {
    user_info_path :: file:filename(),
    sbfolder_path :: file:filename(),
    sbboot_config_path :: file:filename(),
    sbboot_config :: map(),
    online_users = #{} :: #{Username :: binary() => #user_info{}},
    all_users = #{} :: #{Username :: binary() => #user_info{}},
    pending_restart_usernames = [] :: [binary()],
    analyze_pid :: pid()
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
-spec add_user(Username, Password) -> safe_restart_status() when
    Username :: binary(),
    Password :: binary().
add_user(Username, Password) ->
    gen_server:call({global, ?SERVER}, {add_user, Username, Password}).

%%--------------------------------------------------------------------
%% @doc
%% Ban a user with reason.
%%
%% @end
%%--------------------------------------------------------------------
-spec ban_user(Username, BanReason) -> ok when
    Username :: binary(),
    BanReason :: ban_reason().
ban_user(Username, BanReason) ->
    gen_server:call({global, ?SERVER}, {ban_user, BanReason, Username}).

%%--------------------------------------------------------------------
%% @doc
%% Unban user.
%%
%% @end
%%--------------------------------------------------------------------
-spec unban_user(Username) -> ok when
    Username :: binary().
unban_user(Username) ->
    gen_server:call({global, ?SERVER}, {unban_user, Username}).

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
-spec restart_sb() -> ok.
restart_sb() ->
    gen_server:cast({global, ?SERVER}, restart_sb).

%%--------------------------------------------------------------------
%% @doc
%% Send message to starbound server.
%%
%% @end
%%--------------------------------------------------------------------
-spec safe_restart_sb() -> safe_restart_status().
safe_restart_sb() ->
    gen_server:call({global, ?SERVER}, safe_restart_sb).

%%--------------------------------------------------------------------
%% @doc
%% Get pending restart usernames.
%%
%% @end
%%--------------------------------------------------------------------
-spec pending_usernames() -> [binary()].
pending_usernames() ->
    gen_server:call({global, ?SERVER}, pending_usernames).

%%--------------------------------------------------------------------
%% @doc
%% Get server status.
%%
%% @end
%%--------------------------------------------------------------------
-spec server_status() -> ServerStatus :: map().
server_status() ->
    gen_server:call({global, ?SERVER}, server_status).

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

    ServerHomePath = "/root/steamcmd/starbound/storage",
    SbFolderPath = "/root/steamcmd/starbound/linux",
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

    AnalyzePid =
        case whereis(?ANALYZE_PROCESS_NAME) of
            undefined ->
                RawPid = spawn(
                    fun() ->
                        elib:cmd("tail -fn0 " ++ LogPath, fun analyze_log/1)
                    end),
                register(?ANALYZE_PROCESS_NAME, RawPid),
                RawPid;
            ExistingPid ->
                ExistingPid
        end,

    State = #state{
        user_info_path = UsersInfoPath,
        sbfolder_path = SbFolderPath,
        sbboot_config = SbbootConfig,
        sbboot_config_path = SbbConfigPath,
        all_users = AllUsers,
        analyze_pid = AnalyzePid
    },

    {restart_sb_cmd(State), State}.

%%--------------------------------------------------------------------
%% @doc
%% Analyze starbound log.
%%
%% @end
%%--------------------------------------------------------------------
-spec analyze_log(LineBin :: binary()) -> ok.
analyze_log(LineBin) ->
    case re:run(LineBin, <<"^\\[(\\d{2}:\\d{2}:\\d{2}\\.\\d{3})\\]\\s+\\[(\\S*)\\]\\s+(\\S*):\\s+(.*)">>, [{capture, all_but_first, binary}]) of
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
    safe_restart_sb |
    pending_usernames |
    server_status |
    all_users |
    online_users |
    {add_user, Username, Password} |
    {ban_user, Username, BanReason} |
    {unban_user, Username} |
    {user, Username},

    Reply :: add_user_status() |
    term() |
    Users |
    undefined | ok |
    safe_restart_status() |
    {Password, IsPendingRestart, BanReason} |
    [Username] |
    ServerStatus,

    Key :: binary(),
    Username :: binary(),
    Password :: binary(),
    Users :: map(),
    ServerStatus :: map(),
    IsPendingRestart :: boolean(),
    BanReason :: ban_reason(),

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
    UpdatedState = add_user(Username, Password, State),
    user_pending_restart(Username, UpdatedState);
handle_call({ban_user, BanReason, Username}, _From, State) ->
    UpdatedState = ban_user(Username, BanReason, State),

    ok = restart_sb_cmd(State),

    {reply, ok, UpdatedState};
handle_call({unban_user, Username}, _From, State) ->
    UpdatedState = unban_user(Username, State),
    user_pending_restart(Username, UpdatedState);
handle_call({user, Username}, _From, #state{
    all_users = AllUsers,
    pending_restart_usernames = PendingRestartUsernames
} = State) ->
    Result = case maps:get(Username, AllUsers, undefined) of
                 undefined ->
                     undefined;
                 #user_info{
                     password = Password,
                     ban_reason = BanReason
                 } ->
                     {Password, lists:member(Username, PendingRestartUsernames), BanReason}
             end,
    {reply, Result, State};
handle_call(all_users, _From, #state{all_users = AllUsers} = State) ->
    {reply, AllUsers, State};
handle_call(online_users, _From, #state{online_users = OnlineUsers} = State) ->
    {reply, OnlineUsers, State};
handle_call(safe_restart_sb, _From, #state{online_users = OnlineUsers} = State) ->
    case maps:size(OnlineUsers) of
        0 ->
            ok = restart_sb_cmd(State),
            {reply, done, State};
        _Else ->
            {reply, pending, State}
    end;
handle_call(pending_usernames, _From, #state{pending_restart_usernames = PendingRestartUsernames} = State) ->
    {reply, PendingRestartUsernames, State};
handle_call(server_status, _From, #state{online_users = OnlineUsers} = State) ->
    RawMemoryUsages = re:split(os:cmd("free -h"), "\n", [{return, binary}]),
    MemoryUsage = parse_memory_usage(RawMemoryUsages, {}),
    {reply, #{
        is_sb_server_up => case re:run(re:replace(os:cmd("pgrep -f '\\./starbound_server'"), "\n", "", [{return, binary}]), <<"^[0-9]+$">>) of
                            nomatch ->
                                false;
                            _Else ->
                                true
                        end,
        online_users => maps:fold(
            fun(_Username, #user_info{
                player_infos = PlayerInfosMap
            }, AccPlayerInfosMap) ->
                maps:merge(AccPlayerInfosMap, PlayerInfosMap)
            end, #{}, OnlineUsers),
        memory_usage => MemoryUsage
    }, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Parse memory usage from "free -h" to readable text on phone.
%%
%% @end
%%--------------------------------------------------------------------
-spec parse_memory_usage(SrcMemoryUsages, AccMemoryUsages) -> FinalMemoryUsages when
    SrcMemoryUsages :: [binary()],
    Headers :: [binary()],
    AccMemoryUsageBin :: binary(),
    AccMemoryUsages :: {[AccMemoryUsageBin], Headers} | {},
    FinalMemoryUsages :: binary().
parse_memory_usage([RawHeaders | RestMemoryUsages], {}) ->
    [_UselessHead | Headers] = re:split(RawHeaders, <<"\\s+">>, [{return, binary}]),
    parse_memory_usage(RestMemoryUsages, {[], Headers});
parse_memory_usage([MemoryUsageLine | RestMemoryUsages], {AccMemoryUsageBins, Headers}) ->
    [Label | Values] = re:split(MemoryUsageLine, <<"\\s+">>, [{return, binary}]),

    {UpdatedAccMemoryUsages, ParsedMeomoryUsages, _Headers} = lists:foldl(
        fun
            (Value, {AccUpdatedAccMemoryUsages, AccParsedMemoryUsages, [Header | RestHeaders]}) ->
                NewValue =
                    case Value == <<>> of
                        true ->
                            <<>>;
                        false ->
                            <<Header/binary, " ", Label/binary, " ", Value/binary, "\n">>
                    end,

                {ParsedMemoryUsage, RestPasredMemoryUsages} =
                    case AccParsedMemoryUsages of
                        [] ->
                            {<<>>, []};
                        [RawParsedMeomoryUsage | RawRestParsedMemoryUsages] ->
                            {RawParsedMeomoryUsage, RawRestParsedMemoryUsages}
                    end,

                {
                    [<<ParsedMemoryUsage/binary, NewValue/binary>> | AccUpdatedAccMemoryUsages],
                    RestPasredMemoryUsages,
                    RestHeaders
                }
        end, {[], AccMemoryUsageBins, Headers}, Values
    ),

    parse_memory_usage(RestMemoryUsages, {lists:reverse(UpdatedAccMemoryUsages) ++ ParsedMeomoryUsages, Headers});
parse_memory_usage([], {FinalMemoryUsages, _Headers}) ->
    iolist_to_binary(FinalMemoryUsages).

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

    Request :: {analyze_log, #sb_message{}} | restart_sb | stop, % generic term

    State :: #state{},
    NewState :: State,
    Reason :: term(). % generic term
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast({analyze_log, #sb_message{content = Content}}, State) ->
    UpdatedState = handle_logout(Content, State),
    UpdatedState1 = handle_login(Content, UpdatedState),
    UpdatedState2 = handle_restarted(Content, UpdatedState1),
    {noreply, UpdatedState2};
handle_cast(restart_sb, State) ->
    ok = restart_sb_cmd(State),
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%% %%                                   {noreply, State, Timeout} |
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
terminate(_Reason, #state{
    analyze_pid = AnalyzePid
}) ->
    exit(AnalyzePid, normal),
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
    maps:get(<<"serverUsers">>, SbbConfig).

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
    all_users = AllUsers,
    sbboot_config = #{
        <<"serverUsers">> := ExistingServerUsers
    } = SbbConfig
} = State) ->
    UpdatedState = State#state{
        all_users = AllUsers#{
            Username => #user_info{
                username = Username,
                password = Password
            }
        },
        sbboot_config = SbbConfig#{
            <<"serverUsers">> := ExistingServerUsers#{
                Username => #{
                    <<"admin">> => false,
                    <<"password">> => Password
                }
            }
        }
    },

    write_users_info(UpdatedState),

    error_logger:info_msg("Added username:[~p], password:[~p]", [Username, Password]),

    UpdatedState.

%%--------------------------------------------------------------------
%% @doc
%% Ban user
%%
%% @end
%%--------------------------------------------------------------------
-spec ban_user(Username, BanReason, #state{}) -> #state{} when
    Username :: binary(),
    BanReason :: ban_reason().
ban_user(Username, BanReason, #state{
    all_users = AllUsers,
    sbboot_config = #{
        <<"serverUsers">> := ExistingServerUsers
    } = SbbConfig
} = State) ->
    #{Username := UserInfo} = AllUsers,
    UpdatedSbbConfig = SbbConfig#{<<"serverUsers">> := maps:remove(Username, ExistingServerUsers)},

    UpdatedState = State#state{
        all_users = AllUsers#{
            Username := UserInfo#user_info{
                ban_reason = BanReason
            }
        },
        sbboot_config = UpdatedSbbConfig
    },

    write_users_info(UpdatedState),

    error_logger:info_msg("Banned username:[~p]", [Username]),

    UpdatedState.

%%--------------------------------------------------------------------
%% @doc
%% Ban user
%%
%% @end
%%--------------------------------------------------------------------
-spec unban_user(Username, #state{}) -> #state{} when
    Username :: binary().
unban_user(Username, #state{
    all_users = AllUsers,
    sbboot_config = #{
        <<"serverUsers">> := ExistingServerUsers
    } = SbbConfig
} = State) ->
    #{
        Username := #user_info{
            password = Password
        } = UserInfo
    } = AllUsers,

    UpdatedState = State#state{
        all_users = AllUsers#{
            Username => UserInfo#user_info{
                ban_reason = undefined
            }
        },
        sbboot_config = SbbConfig#{
            <<"serverUsers">> := ExistingServerUsers#{
                Username => #{
                    <<"admin">> => false,
                    <<"password">> => Password
                }
            }
        }
    },

    write_users_info(UpdatedState),
    error_logger:info_msg("Unbanned username:[~p], password:[~p]", [Username, Password]),

    UpdatedState.

%%--------------------------------------------------------------------
%% @doc
%% Handle login
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_login(Content :: binary(), #state{}) -> #state{}.
handle_login(Content, #state{
    online_users = OnlineUsers,
    all_users = AllUsers
} = State) ->
    case re:run(Content, <<"^Logged\\sin\\saccount\\s''(\\S*)''\\sas\\splayer\\s'(.*)'\\sfrom\\saddress\\s(0000:0000:0000:0000:0000:ffff:\\S{4}:\\S{4})">>, [{capture, all_but_first, binary}]) of
        {match, [Username, PlayerName, PlayerAddr]} ->
            Timestamp = os:timestamp(),
            {ok, Ipv4Addr} = elib:ipv6_2_ipv4(PlayerAddr),

            CurPlayerInfo = #player_info{
                player_name = PlayerName,
                ip_addr = Ipv4Addr,
                last_login_time = Timestamp
            },

            #{Username := #user_info{
                player_infos = PlayerInfos
            } = ExistingUser} = AllUsers,

            #{Username := UserInfo} = UpdatedAllUsers = AllUsers#{
                Username := ExistingUser#user_info{
                    last_login_time = Timestamp,
                    player_infos = PlayerInfos#{PlayerName => CurPlayerInfo}
                }
            },

            StateWithAllUsers = State#state{
                all_users = UpdatedAllUsers
            },

            UpdatedState =
                case maps:get(Username, OnlineUsers, undefined) of
                    undefined ->
                        error_logger:info_msg("User <~p> Player <~p> logged in.~n", [Username, PlayerName]),
                        ReturnState = StateWithAllUsers#state{
                            online_users = OnlineUsers#{
                                Username => UserInfo
                            }
                        },
                        write_users_info(ReturnState),
                        ReturnState;
                    _DuplicatedLogin ->
                        error_logger:info_msg("Ban User <~p> due to duplicated login at same time.~nPlayer name: <~p>~n", [Username, PlayerName]),
                        ReturnState = ban_user(Username, simultaneously_duplicated_login, StateWithAllUsers),
                        ok = restart_sb_cmd(ReturnState),
                        ReturnState
                end,

            UpdatedState;
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
    online_users = OnlineUsers,
    pending_restart_usernames = PendingRestartUsernames
} = State) ->
    case re:run(Content, <<"^Client\\s+'(.*)'\\s+<(\\d*)>\\s+\\((\\S*\\))\\sdisconnected">>, [{capture, all_but_first, binary}]) of
        {match, [PlayerName, _ServerLoginCount, _PlayerAddr]} ->
            LogoutUsername = maps:fold(
                fun
                    (Username, #user_info{
                        player_infos = #{
                            PlayerName := #player_info{}
                        }
                    }, undefined) ->
                        Username;
                    (_Username, #user_info{}, AccUsername) ->
                        AccUsername
                end, undefined, OnlineUsers),

            UpdatedOnlineUsers = maps:remove(LogoutUsername, OnlineUsers),

            UpdatedState = State#state{
                online_users = UpdatedOnlineUsers
            },

            ok = case maps:size(UpdatedOnlineUsers) == 0 andalso length(PendingRestartUsernames) > 0 of
                     true ->
                         restart_sb_cmd(UpdatedState);
                     false ->
                         ok
                 end,

            error_logger:info_msg("Player <~p> logged out.~n", [PlayerName]),

            UpdatedState;
        nomatch ->
            State
    end.

%%--------------------------------------------------------------------
%% @doc
%% Handle restarted
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_restarted(Content :: binary(), #state{}) -> #state{}.
handle_restarted(Content, State) ->
    case re:run(Content, <<"^Writing\\sruntime\\sconfiguration\\sto">>, []) of
        {match, _Match} ->
            error_logger:info_msg("Server restarted~n"),
            State#state{
                online_users = #{},
                pending_restart_usernames = []
            };
        nomatch ->
            State
    end.

%%--------------------------------------------------------------------
%% @doc
%% User pending restart
%%
%% @end
%%--------------------------------------------------------------------
-spec user_pending_restart(Username :: binary(), #state{}) -> {reply, safe_restart_status(), #state{}}.
user_pending_restart(Username, #state{
    online_users = OnlineUsers,
    pending_restart_usernames = PendingRestartUsernames
} = State) ->
    case maps:size(OnlineUsers) of
        0 ->
            ok = restart_sb_cmd(State),
            {reply, done, State};
        _Else ->
            {reply, pending, State#state{
                pending_restart_usernames = [Username | PendingRestartUsernames]
            }}
    end.

%%--------------------------------------------------------------------
%% @doc
%% Write users info to local file
%%
%% @end
%%--------------------------------------------------------------------
-spec write_users_info(#state{}) -> pid().
write_users_info(#state{
    all_users = AllUsers,
    user_info_path = UsersInfoPath,
    sbboot_config = SbbConfig,
    sbboot_config_path = SbbConfigPath
}) ->
    spawn(
        fun() ->
            UpdatedAllUsersBin = io_lib:format("~tp.", [AllUsers]),
            file:write_file(UsersInfoPath, UpdatedAllUsersBin),

            SbbConfigBin = json:to_binary(SbbConfig),
            file:write_file(SbbConfigPath, SbbConfigBin)
        end).

%%--------------------------------------------------------------------
%% @doc
%% Restart Sb server cmd.
%%
%% @end
%%--------------------------------------------------------------------
-spec restart_sb_cmd(#state{}) -> ok.
restart_sb_cmd(#state{sbfolder_path = SbFolderPath}) ->
    error_logger:info_msg("Execute server restart command~n"),
    os:cmd("cd " ++ SbFolderPath ++ ";./sb_server.sh restart"),
    ok.