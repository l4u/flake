%%%
%%% Copyright 2012, Boundary
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%

%%% Refactored 2012 / Bjorn Jensen-Urstad

%%%_* Module declaration ===============================================
-module(flake).

%%%_* Exports ==========================================================
-export([ id_bin/0
        , id_str/1
        , id_int/0
        ]).

%%%_* Code =============================================================
%%%_ * API -------------------------------------------------------------
%% @doc uid in binary format
id_bin() ->
  flake_server:id().

%% @doc uid in string format
id_str(Base) ->
  case flake_server:id() of
    {ok, <<Id:128/integer>>} ->
      {ok, flake_util:integer_to_list(Id, Base)};
    {error, Rsn} ->
      {error, Rsn}
  end.

%% @doc uid in integer format
id_int() ->
  case flake_server:id() of
    {ok, <<Id:128/integer>>} -> {ok, Id};
    {error, Rsn}             -> {error, Rsn}
  end.

%%%_* Tests ============================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

types_test() ->
  flake_test:test_init(),
  application:start(flake),
  {ok, Bin} = flake:id_bin(),
  {ok, Str} = flake:id_str(10),
  {ok, Int} = flake:id_int(),

  true = erlang:is_binary(Bin),
  true = erlang:is_list(Str),
  true = erlang:is_integer(Int),
  application:stop(flake),
  flake_test:test_end().

%% test that id's are sequential
-define(n, 10000).
id_prop_sequential_test() ->
  flake_test:test_init(),
  ok = application:start(flake),
  F = fun(_N, {Int0, Int1}) when Int0 < Int1 ->
          {Int1, flake:id_int()}
      end,
  Int0 = flake:id_int(),
  Int1 = flake:id_int(),
  lists:foldl(F, {Int0, Int1}, lists:seq(1, ?n)),
  application:stop(flake),
  flake_test:test_end().

id_prop_test() ->
  flake_test:test_init(),
  application:start(flake),
  Ts1 = flake_util:now_in_ms(),
  timer:sleep(2),
  {ok, <<FlakeTs1:64/integer,
         FlakeMac1:6/binary,
         FlakeSeqno1:16/integer>>} = flake:id_bin(),
  timer:sleep(2),
  Ts2 = flake_util:now_in_ms(),
  timer:sleep(2),
  {ok, <<FlakeTs2:64/integer,
         FlakeMac2:6/binary,
         FlakeSeqno2:16/integer>>} = flake:id_bin(),
  %% properties that should hold
  true = Ts1 < FlakeTs1,
  true = FlakeTs1 < Ts2,
  true = Ts2 < FlakeTs2,
  true = FlakeMac1 =:= FlakeMac2,
  true = FlakeSeqno1 =:= 0,
  true = FlakeSeqno2 =:= 0,
  application:stop(flake),
  flake_test:test_end().

%% generate a bunch of id's in parallell, check uniqueness
-define(processes, 16).
-define(requests, 5000).
parallell_test() ->
  flake_test:test_init(),
  application:start(flake),
  Pids  = [start_worker(self()) || _N <- lists:seq(1, ?processes)],
  Res   = [receive {Pid, Ids} -> Ids end || Pid <- Pids],
  ?processes * ?requests = length(lists:usort(lists:concat(Res))),
  application:stop(flake),
  flake_test:test_end().

start_worker(Daddy) ->
  F = fun() ->
          Daddy ! {self(), [begin
                              {ok, Bin} = flake:id_bin(),
                              Bin
                            end || _N <- lists:seq(1, ?requests)]}
      end,
  proc_lib:spawn_link(F).


time_server_updates_test() ->
  flake_test:test_init(),
  {ok, Interval} = application:get_env(flake, interval),
  application:start(flake),
  {ok, _Bin1} = flake:id_bin(),
  timer:sleep(Interval * 2 + 1),
  {ok, _Bin2} = flake:id_bin(),
  application:stop(flake),
  flake_test:test_end().

%% test that delayed start works
start_stop_test() ->
  flake_test:test_init(),
  application:start(flake),
  {ok, _} = flake:id_bin(),
  application:stop(flake),
  application:start(flake),
  {ok, _} = flake:id_bin(),
  application:stop(flake),
  flake_test:test_end().

stray_messages_test() ->
  flake_test:test_init(),
  application:start(flake),
  whereis(flake_server) ! foo,
  whereis(flake_time_server) ! baz,
  {ok, _} = flake:id_bin(),
  application:stop(flake),
  flake_test:test_end().

-else.
-endif.

%%%_* Emacs ============================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
