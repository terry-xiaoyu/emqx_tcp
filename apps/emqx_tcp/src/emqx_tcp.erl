-module(emqx_tcp).

%% API
-export([load_start/1, load_stop/0, send/1, do_load/1]).

-export([start/0]).

-export([start_link/2, init/2, loop/2]).

-define(TCP_OPTIONS, [binary, {reuseaddr, true}, {nodelay, false}]).

load_start(Interval) ->
  Pid = spawn(?MODULE, do_load, [Interval]),
  register(load_send, Pid).
load_stop() ->
  load_send ! stop,
  unregister(load_send).

do_load(Interval) ->
  timer:send_interval(Interval, {send_msg, <<"hi">>}),
  do_load_loop(Interval).

do_load_loop(Interval) ->
  receive
    {send_msg, Data} ->
        send(Data),
        do_load_loop(Interval);
    stop -> ok
  end.

send(Data) ->
  Pids = ets:lookup(conns, pids),
  lists:foreach(fun({pids, C}) ->
    C ! {send, Data}
  end,Pids).

start() -> start(9899).
start(Port) when is_integer(Port) ->
    SockOpts = [{tcp_options,[{backlog,1024},
                     {send_timeout,15000},
                     {send_timeout_close,true},
                     {nodelay,true},
                     {reuseaddr,true}]},
                {acceptors,8},
                {max_connections,1024000},
                {access_rules,[{allow,all}]}],
    MFArgs = {?MODULE, start_link, []},
    esockd:open(emqx_tcp, Port, SockOpts, MFArgs).

%%--------------------------------------------------------------------
%% esockd callback
%%--------------------------------------------------------------------

start_link(Transport, Sock) ->
	{ok, spawn_link(?MODULE, init, [Transport, Sock])}.

init(Transport, Sock) ->
    case Transport:wait(Sock) of
        {ok, NewSock} ->
          ets:insert(conns, {pids, self()}),
          loop(Transport, NewSock);
        Error -> Error
    end.

loop(Transport, Sock) ->
  case Transport:recv(Sock, 0) of
		{ok, Data} ->
			{ok, Peername} = Transport:peername(Sock),
			io:format("~s - ~s~n", [esockd_net:format(peername, Peername), Data]),
			Transport:send(Sock, <<"this is server!">>),
      loop(Transport, Sock);
    {send, Data} ->
      ok = Transport:send(Sock, Data),
      loop(Transport, Sock);
		{error, Reason} ->
			io:format("TCP ~s~n", [Reason]),
			{stop, Reason}
	end.

%loop(Transport, Sock) ->
%	receive
%		{send, Data} ->
%      {ok, Peername} = Transport:peername(Sock),
%      io:format("send msg... sock:~p, peername:~p~n", [Sock, Peername]),
%			ok = Transport:send(Sock, Data),
%      loop(Transport, Sock);
%		stop ->
%			{stop, shutdown};
%    Msg ->
%      io:format("emqx tcp received: ~p~n", [Msg])
%	end.