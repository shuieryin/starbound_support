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
    stop/1,
    init/2
]).

-record(state, {}).

-define(SBBCONFIG_PATH, "/root/steamcmd/starbound/storage/starbound_server.config").

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
start(normal, [AppNameStr] = _StartArgs) ->
    AppName = list_to_atom(AppNameStr),
    Dispatch = cowboy_router:compile(
        [
            {
                '_',
                [
                    {
                        "/apis/[...]",
                        ?MODULE,
                        {priv_dir, AppName, "assets"}
                    },

                    {
                        "/admin/[...]",
                        cowboy_static,
                        {
                            priv_dir,
                            AppName,
                            "admin_html",
                            [
                                {mimetypes, cow_mimetypes, all}
                            ]
                        }
                    }
                ]
            }
        ]
    ),

    AppNameBin = list_to_binary(AppNameStr),

    Port = 8080,
    case cowboy:start_clear(binary_to_atom(<<AppNameBin/binary, "_listener">>, utf8), [{port, Port}], #{env => #{dispatch => Dispatch}}) of
        {error, Reason} ->
            error_logger:error_msg("websockets could not be started -- port ~p probably in use~nReason:~p~n", [Port, Reason]),
            init:stop();
        {ok, _Pid} ->
            io:format("websockets started on port:~p~nLoad the page http://localhost:~p/ in your browser~n", [Port, Port])
    end,

    {ok, Pid} = starbound_support_sup:start_link(?SBBCONFIG_PATH),
    ok = elib:show_errors(20),
    {ok, Pid, #state{}}.

%%--------------------------------------------------------------------
%% @doc
%% Handles a request. This function is spawned by cowboy_server
%% whenever a request comes in.
%%
%% @end
%%--------------------------------------------------------------------
-spec init(Req, Env) -> SocketInfo | HttpReply when
    SocketInfo :: {cowboy_websocket, Req, Pid},
    Req :: cowboy_req:req(),
    Pid :: pid(),
    HttpReply :: {ok, Resp, cowboy_middleware:env()},
    Resp :: cowboy_req:req(),
    Env :: {priv_dir, AppName :: atom(), StaticFolder :: list()}.
init(Req, {priv_dir, AppName, StaticFolder} = Env) ->
    % error_logger:info_msg("Request raw:~p~nEnv:~p~n", [Req, Env]),
    Resource = path(Req),
    % error_logger:info_msg("Resource:~p~n", [Resource]),
    case Resource of
        ["/", "websocket", UriStr] ->
            Self = self(),
            Mod = list_to_atom(UriStr),
            Pid = spawn_link(Mod, start, [Self]),
            {cowboy_websocket, Req, Pid};
        ["/", "assets", Filename] ->
            StaticFolderPath = filename:join([code:priv_dir(AppName), StaticFolder, Filename]),
            ReturnContent =
                case file:read_file(StaticFolderPath) of
                    {ok, FileBin} ->
                        FileBin;
                    Error ->
                        list_to_binary(io_lib:format("~p", [Error]))
                end,

            {ok, cowboy_req:reply(200, #{}, ReturnContent, Req), Env};
        _Resource ->
            error_logger:info_msg("not found:~p~n", [_Resource]),
            {ok, cowboy_req:reply(200, #{}, <<>>, Req), Env}
    end.

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

%%--------------------------------------------------------------------
%% @doc
%% Gets the request url path from request content and split it in
%% list with separator "/".
%%
%% @end
%%--------------------------------------------------------------------
-spec path(Req) -> Paths when
    Req :: cowboy_req:req(),
    Paths :: [file:name_all()].
path(Req) ->
    Path = cowboy_req:path(Req),
    filename:split(binary_to_list(Path)).