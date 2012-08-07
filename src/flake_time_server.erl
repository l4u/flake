%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc saves timestamps with configurable interval.
%%% @copyright Bjorn Jensen-Urstad 2012
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration ===============================================
-module(flake_time_server).
-behaviour(gen_server).

%%%_* Exports ==========================================================
-export([ start_link/1
        , subscribe/0
        , unsubscribe/0
        ]).

-export([ init/1
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , terminate/2
        , code_change/3
        ]).

-export([real_file/1]). %% testing

%%%_* Code =============================================================
%%%_ * Types -----------------------------------------------------------
-record(s, { path      :: list()
           , tref      :: any()
           , ts        :: integer()
           , subs = [] :: list()
           }).
%%%_ * API -------------------------------------------------------------
start_link(Args) ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, Args, []).

subscribe() ->
  gen_server:call(?MODULE, subscribe, infinity).

unsubscribe() ->
  gen_server:call(?MODULE, unsubscribe).

%%%_ * gen_server callbacks --------------------------------------------
init(_Args) ->
  erlang:process_flag(trap_exit, true),
  {ok, Path}     = application:get_env(flake, timestamp_path),
  {ok, Downtime} = application:get_env(flake, allowable_downtime),
  {ok, Interval} = application:get_env(flake, interval),
  
  case filelib:is_file(real_file(Path)) of
    true  -> do_init_old(Path, Downtime, Interval);
    false -> do_init_new(Path, Downtime, Interval)
  end.

terminate(_Rsn, #s{tref=TRef}) ->
  _ = timer:cancel(TRef),
  ok.

handle_call(subscribe, {Pid, _} = _From, #s{subs=Subs} = S) ->
  case lists:keyfind(Pid, 1, Subs) of
    {value, {Pid, _Ref}} ->
      {reply, {error, already_subscribed}, S};
    false ->
      Ref = erlang:monitor(process, Pid),
      {reply, {ok, S#s.ts}, S#s{subs=[{Pid,Ref}|Subs]}}
  end;

handle_call(unsubscribe, {Pid, _} = _From, #s{subs=Subs0} = S) ->
  case lists:keytake(Pid, 1, Subs0) of
    {value, {Pid, Ref}, Subs} ->
      erlang:demonitor(Ref, [flush]),
      {reply, ok, S#s{subs=Subs}};
    false ->
      {reply, {error, not_subscribed}, S}
  end.

handle_cast(stop, S) ->
  {stop, normal, S}.

handle_info(save, S) ->
  case update_ts(S#s.path, S#s.ts) of
    {ok, Ts}     -> notify_subscribers(Ts, S#s.subs),
                    {noreply, S#s{ts = Ts}};
    {error, Rsn} -> {stop, Rsn, S}
  end;

handle_info({'DOWN', Ref, process, Pid, _Rsn}, S) ->
  {value, {Pid, Ref}, Subs} = lists:keytake(Pid, 1, S#s.subs),
  erlang:demonitor(Ref, [flush]),
  {noreply, S#s{subs=Subs}};

handle_info(_Msg, S) ->
  {noreply, S}.

code_change(_OldVsn, S, _Extra) ->
  {ok, S}.

%%%_ * Internals -------------------------------------------------------
do_init_old(Path, Downtime, Interval) ->
  Now  = flake_util:now_in_ms(),
  Then = read_ts(Path),
  io:format("NOW: ~p~n", [Now]),
  io:format("THEN: ~p~n", [Then]),
  if Then > Now            -> {stop, clock_running_backwards};
     Now - Then > Downtime -> {stop, clock_advanced};
     true ->
      maybe_delay(Then + Interval * 2 - Now),
      case update_ts(Path, Now) of
        {ok, Ts}     ->
          {ok, TRef} = timer:send_interval(Interval, save),
          {ok, #s{path = Path, tref = TRef, ts = Ts}};
        {error, Rsn} -> {stop, Rsn}
      end
  end.

do_init_new(Path, _Downtime, Interval) ->
  Now = flake_util:now_in_ms(),
  ok  = filelib:ensure_dir(filename:join([Path, "dummy"])),
  ok  = write_ts(Path, Now),
  {ok, TRef} = timer:send_interval(Interval, save),
  {ok, #s{path = Path, tref = TRef, ts = Now}}.

maybe_delay(Delay) when Delay > 0 ->
  error_logger:info_msg("~p: delaying startup = ~p~n", [?MODULE, Delay]),
  timer:sleep(Delay);
maybe_delay(_Delay) -> ok.

temp_file(Path) -> filename:join(Path, "flake.tmp").
real_file(Path) -> filename:join(Path, "flake").

update_ts(Path, OldTs) ->
  case flake_util:now_in_ms() of
    Ts when Ts < OldTs -> {error, clock_running_backwards};
    Ts                 -> ok = write_ts(Path, Ts),
                          {ok, Ts}
  end.

write_ts(Path, Ts) ->
  Temp = temp_file(Path),
  Real = real_file(Path),
  ok = file:write_file(Temp, erlang:term_to_binary(Ts)),
  ok = file:rename(Temp, Real).

read_ts(Path) ->
  {ok, Bin} = file:read_file(real_file(Path)),
  erlang:binary_to_term(Bin).

notify_subscribers(Ts, Subs) ->
  lists:foreach(fun({Pid, _Ref}) -> Pid ! {ts, Ts} end, Subs).

%%%_* Tests ============================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

clock_backwards_test() ->
  flake_test:test_init(),
  {ok, Path} = application:get_env(flake, timestamp_path),
  write_ts(Path, flake_util:now_in_ms() + 5000),
  erlang:process_flag(trap_exit, true),
  {error, clock_running_backwards} = flake_time_server:start_link([]),
  flake_test:test_end().

clock_advanced_test() ->
  flake_test:test_init(),
  {ok, Path}     = application:get_env(flake, timestamp_path),
  {ok, Downtime} = application:get_env(flake, allowable_downtime),
  write_ts(Path, flake_util:now_in_ms() - Downtime -1),
  erlang:process_flag(trap_exit, true),
  {error, clock_advanced} = flake_time_server:start_link([]),
  flake_test:test_end().

rw_timestamp_test() ->
  flake_test:test_init(),
  {ok, Path} = application:get_env(flake, timestamp_path),
  Ts0             = 0,
  Ts1             = 1,
  ok  = write_ts(Path, Ts0),
  Ts0 = read_ts(Path),
  ok  = write_ts(Path, Ts1),
  Ts1 = read_ts(Path),
  flake_test:test_end().

subscriber_test() ->
  flake_test:test_init(),
  erlang:process_flag(trap_exit, true),
  {ok, Pid1} = flake_time_server:start_link([]),
  {ok, Pid2} = flake_server:start_link([]),
  exit(Pid2, die),
  timer:sleep(10),
  {ok, Pid3} = flake_server:start_link([]),
  exit(Pid3, die),
  exit(Pid1, die),
  flake_test:test_end().

-else.
-endif.

%%%_* Emacs ============================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
