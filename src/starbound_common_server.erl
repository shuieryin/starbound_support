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
-define(TEMPERATURE_FILEPATH, "/root/starbound_support/temperature").
-define(CPU_USAGE_FILEPATH, "/root/starbound_support/cpuusage").

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

-type add_user_status() :: ok | user_exist.
-type safe_restart_status() :: done | pending.
-type ban_reason() :: simultaneously_duplicated_login | login_always_cause_server_down | undefined.
-type server_status() :: #{
is_sb_server_up => boolean(),
online_users => #{Username :: binary() => #player_info{}},
memory_usage => binary(),
temperature => binary(),
cpu_usage => binary()
}.

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
    State = gen_server:call({global, ?SERVER}, server_state),
    UpdatedState = ban_user(Username, BanReason, State),
    ok = gen_server:cast({global, ?SERVER}, {update_state, UpdatedState}),
    restart_sb_cmd(State).

%%--------------------------------------------------------------------
%% @doc
%% Unban user.
%%
%% @end
%%--------------------------------------------------------------------
-spec unban_user(Username) -> safe_restart_status() when
    Username :: binary().
unban_user(Username) ->
    State = gen_server:call({global, ?SERVER}, server_state),
    UpdatedState = unban_user(Username, State),
    {Status, FinalState} = user_pending_restart(Username, UpdatedState),
    ok = gen_server:cast({global, ?SERVER}, {update_state, FinalState}),
    Status.

%%--------------------------------------------------------------------
%% @doc
%% Add username and password.
%%
%% @end
%%--------------------------------------------------------------------
-spec user(Username) -> undefined | {Password, IsPendingRestart, BanReason} when
    Username :: binary(),
    Password :: binary(),
    IsPendingRestart :: boolean(),
    BanReason :: binary().
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
    spawn(
        fun() ->
            State = gen_server:call({global, ?SERVER}, server_state),
            ok = restart_sb_cmd(State)
        end),
    ok.

%%--------------------------------------------------------------------
%% @doc
%% Send message to starbound server.
%%
%% @end
%%--------------------------------------------------------------------
-spec safe_restart_sb() -> safe_restart_status().
safe_restart_sb() ->
    #state{online_users = OnlineUsers} = State = gen_server:call({global, ?SERVER}, server_state),
    case maps:size(OnlineUsers) of
        0 ->
            ok = restart_sb_cmd(State),
            done;
        _Else ->
            pending
    end.

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
-spec server_status() -> ServerStatus :: server_status().
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

    IsSbServerUp = is_sb_server_up(),
    OnlineUsers =
        case IsSbServerUp of
            false ->
                #{};
            true ->
                elib:for_each_line_in_file(LogPath, fun analyze_log/1)
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
        online_users = OnlineUsers,
        analyze_pid = AnalyzePid
    },

    {case IsSbServerUp of
         true ->
             ok;
         false ->
             restart_sb_cmd(State)
     end, State}.

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
    pending_usernames |
    all_users |
    online_users |
    server_state |
    safe_start_cmd |
    {user, Username} |
    {add_user, Username, Password} |
    server_status,

    Reply ::
    add_user_status() |
    Users,
    Username :: binary(),
    Password :: binary(),

    Key :: binary(),
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
handle_call(all_users, _From, #state{all_users = AllUsers} = State) ->
    {reply, AllUsers, State};
handle_call(online_users, _From, #state{online_users = OnlineUsers} = State) ->
    {reply, OnlineUsers, State};
handle_call(pending_usernames, _From, #state{pending_restart_usernames = PendingRestartUsernames} = State) ->
    {reply, PendingRestartUsernames, State};
handle_call(server_state, _From, State) ->
    {reply, State, State};
handle_call(safe_start_cmd, _From, State) ->
    {reply, start_sb_cmd(State), State};
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
handle_call({add_user, Username, Password}, _From, State) ->
    UpdatedState = add_user(Username, Password, State),
    {Status, FinalState} = user_pending_restart(Username, UpdatedState),
    {reply, Status, FinalState};
handle_call(server_status, _From, #state{online_users = OnlineUsers} = State) ->
    %% Collect memory usage - START
    RawMemoryUsages = re:split(os:cmd("free"), "\n", [{return, binary}]),
    {MemoryUsage, #{
        <<"total_Mem">> := TotalMem,
        <<"used_Mem">> := UsedMem
    } = ValuesMap} = parse_memory_usage(RawMemoryUsages, {}, #{}),
    error_logger:info_msg("Raw memroy usage:~p~nMap:~p~n", [MemoryUsage, ValuesMap]),
    MemoryUsageBin = float_to_binary(UsedMem / TotalMem * 100, [{decimals, 2}]),
    %% Collect memory usage - END

    %% Collect temperature - START
    TemperatureBin =
        case file:read_file(?TEMPERATURE_FILEPATH) of
            {ok, RetTemperatureBin} ->
                RetTemperatureBin;
            {error, _ReasonTemp} ->
                <<>>
        end,
    %% Collect temperature - END

    %% Collect cpu usage - START
    CpuUsageBin =
        case file:read_file(?CPU_USAGE_FILEPATH) of
            {ok, RetCpuUsageBin} ->
                RetCpuUsageBin;
            {error, _ReasonCpu} ->
                <<>>
        end,
    %% Collect cpu usage - END

    {reply, #{
        is_sb_server_up => is_sb_server_up(),
        online_users => maps:fold(
            fun(_Username, #user_info{
                player_infos = PlayerInfosMap
            }, AccPlayerInfosMap) ->
                maps:merge(AccPlayerInfosMap, PlayerInfosMap)
            end, #{}, OnlineUsers),
        memory_usage => <<MemoryUsageBin/binary, "%">>,
        temperature => TemperatureBin,
        cpu_usage => <<CpuUsageBin/binary, "%">>
    }, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Parse memory usage from "free" to readable text on phone.
%%
%% @end
%%--------------------------------------------------------------------
-spec parse_memory_usage(SrcMemoryUsages, AccMemoryUsages, AccValuesMap) -> {FinalMemoryUsages, FinalValuesMap} when
    SrcMemoryUsages :: [binary()],
    Headers :: [binary()],
    AccMemoryUsageBin :: binary(),
    AccMemoryUsages :: {[AccMemoryUsageBin], Headers} | {},
    FinalMemoryUsages :: binary(),
    AccValuesMap :: map(),
    FinalValuesMap :: AccValuesMap.
parse_memory_usage([RawHeaders | RestMemoryUsages], {}, AccValuesMap) ->
    [_UselessHead | Headers] = re:split(RawHeaders, <<"\\s+">>, [{return, binary}]),
    parse_memory_usage(RestMemoryUsages, {[], Headers}, AccValuesMap);
parse_memory_usage([MemoryUsageLine | RestMemoryUsages], {AccMemoryUsageBins, Headers}, AccValuesMap) ->
    [Label | Values] = re:split(MemoryUsageLine, <<"\\s+">>, [{return, binary}]),

    {UpdatedAccMemoryUsages, ParsedMeomoryUsages, _Headers, UpdatedAccValuesMap} = lists:foldl(
        fun
            (Value, {AccUpdatedAccMemoryUsages, AccParsedMemoryUsages, [Header | RestHeaders], InnerAccValuesMap}) ->
                {NewValue, UpdatedInnerAccValuesMap} =
                    case Value == <<>> of
                        true ->
                            <<>>;
                        false ->
                            LabelWithoutColon = <<<<X>> || <<X:8>> <= Label, <<X:8>> =/= <<$:>>>>,
                            FinalLabel = <<Header/binary, "_", LabelWithoutColon/binary>>,
                            {<<FinalLabel/binary, ": ", Value/binary, "\n">>, InnerAccValuesMap#{FinalLabel => list_to_integer(binary_to_list(Value))}}
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
                    RestHeaders,
                    UpdatedInnerAccValuesMap
                }
        end, {[], AccMemoryUsageBins, Headers, AccValuesMap}, Values
    ),

    parse_memory_usage(RestMemoryUsages, {lists:reverse(UpdatedAccMemoryUsages) ++ ParsedMeomoryUsages, Headers}, UpdatedAccValuesMap);
parse_memory_usage([], {FinalMemoryUsages, _Headers}, FinalValuesMap) ->
    {iolist_to_binary(FinalMemoryUsages), FinalValuesMap}.

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

    Request ::
    {analyze_log, #sb_message{}},

    State :: #state{},
    NewState :: State,
    Reason :: term(). % generic term
handle_cast({analyze_log, #sb_message{content = Content}}, State) ->
    UpdatedState = handle_logout(Content, State),
    UpdatedState1 = handle_login(Content, UpdatedState),
    UpdatedState2 = handle_restarted(Content, UpdatedState1),
    UpdatedState3 = handle_errors(Content, UpdatedState2),
    {noreply, UpdatedState3}.

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
    all_users = AllUsers,
    sbboot_config = #{
        <<"serverUsers">> := ExistingServerUsers
    }
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

            #user_info{
                player_infos = PlayerInfos
            } = ExistingUser =
                case maps:get(Username, AllUsers, undefined) of
                    undefined ->
                        #{Username := #{
                            <<"password">> := Password
                        }} = ExistingServerUsers,
                        RawExistingUser = #user_info{
                            username = Username,
                            password = Password
                        },

                        AddMissingUserState = State#state{
                            all_users = AllUsers#{
                                Username => RawExistingUser
                            }
                        },

                        write_users_info(AddMissingUserState),
                        RawExistingUser;
                    Found ->
                        Found
                end,

            #{Username := UserInfo} = UpdatedAllUsers = AllUsers#{
                Username => ExistingUser#user_info{
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
                                Username => UserInfo#user_info{
                                    player_infos = #{
                                        PlayerName => CurPlayerInfo
                                    }
                                }
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
%% Handle errors
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_errors(Content :: binary(), #state{}) -> #state{}.
handle_errors(Content, State) ->
    case re:run(Content, <<"^Segfault\\sEncountered!">>, []) of
        {match, _Match} ->
            error_logger:info_msg("Restart server due to ~p~n", [Content]),
            ok = restart_sb_cmd(State);
        nomatch ->
            do_nothing
    end,
    State.

%%--------------------------------------------------------------------
%% @doc
%% User pending restart
%%
%% @end
%%--------------------------------------------------------------------
-spec user_pending_restart(Username :: binary(), #state{}) -> {safe_restart_status(), #state{}}.
user_pending_restart(Username, #state{
    online_users = OnlineUsers,
    pending_restart_usernames = PendingRestartUsernames
} = State) ->
    case maps:size(OnlineUsers) of
        0 ->
            ok = restart_sb_cmd(State),
            {done, State};
        _Else ->
            {pending, State#state{
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
%% Check if SB server is up
%%
%% @end
%%--------------------------------------------------------------------
-spec is_sb_server_up() -> boolean().
is_sb_server_up() ->
    case re:run(re:replace(os:cmd("pgrep -f '\\./starbound_server'"), "\n", "", [{return, binary}]), <<"^[0-9]+$">>) of
        nomatch ->
            false;
        _Else ->
            true
    end.

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

%%--------------------------------------------------------------------
%% @doc
%% Start Sb server cmd.
%%
%% @end
%%--------------------------------------------------------------------
-spec start_sb_cmd(#state{}) -> binary().
start_sb_cmd(#state{sbfolder_path = SbFolderPath}) ->
    re:replace(os:cmd("cd " ++ SbFolderPath ++ "; ./sb_server.sh start"), "\n", "", [{return, binary}]).