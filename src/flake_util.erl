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

%%%_* Module declaration ===============================================
-module (flake_util).
-compile(no_auto_import, [integer_to_list/2]).

%%%_* Exports ==========================================================
-export([ mk_id/3
        , now_in_ms/0
        , get_mac_addr/1
        , mac_addr_to_int/1
        , read_timestamp/1
        , write_timestamp/2

	, as_list/2,
        ]).

%%%_* Code =============================================================
%%%_ * API -------------------------------------------------------------

%% @doc mac addr as a 6 element/byte array
get_mac_addr(Interface) ->
  case lists:keyfind(Interface, 1, inet:getifaddrs()) of
    {Interface, Props} ->
      case lists:keyfind(hwaddr, 1, Props) of
        {hwaddr, Mac} -> {ok, Mac};
        false         -> {error, mac_not_found}
      end;
    false ->
      {error, interface_not_found}
  end.

mac_addr_to_int(Mac) ->
  <<MacInt:48/integer>> = erlang:list_to_binary(HwAddr),
  MacInt.

now_in_ms() ->
  {Ms, S, Us} = erlang:now(),
  1000000000*Ms + S*1000 + erlang:trunc(Us/1000).

mk_id(Ts, Mac, Seqno) ->
  <<Ts:64/integer, Mac:48/integer, Seqno:16/integer>>.

%%
%% n.b. - unique_id_62/0 and friends pulled from riak
%%
%% @doc Convert an integer to its string representation in the given
%%      base.  Bases 2-62 are supported.
integer_to_list(I, Base)
  when erlang:is_integer(I),
       erlang:is_integer(Base),
       Base >= 2,
       Base =< 36 ->
  erlang:integer_to_list(I, Base);
integer_to_list(I, Base)
  when erlang:is_integer(I),
       erlang:is_integer(Base),
       Base >= 2,
       Base =< 1+$Z-$A+10+1+$z-$a -> %% 62
  case I < 0 of
    true  -> [$-|as_list(-I, Base, [])];
    false -> as_list(I, Base, [])
  end.

integer_to_list(I0, Base, R0) ->
  R1 = case I0 rem Base of
         D when D >= 36 -> [D-36+$a|R0];
         D when D >= 10 -> [D-10+$A|R0];
         D              -> [D+$0   |R0]
       end,
  case I0 div Base of
    0  -> R1;
    I1 -> integer_to_list(I1, Base, R1)
  end.

write_timestamp(File, Ts) ->
  file:write_file(File, erlang:term_to_binary(Ts)).

read_timestamp(File) ->
  case file:read_file(File) of
    {ok, Bin}       -> {ok, erlang:binary_to_term(Bin)};
    {error, enoent} -> {error, enoent};
    {error, Rsn}    -> {error, Rsn}
  end.

%%%_* Tests ============================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

-define(tmpfile, "/tmp/flake.tmp").
timestamp_test() ->
  file:delete(?tmpfile),
  Ts = now_in_ms(),
  {error, enoent} = read_timestamp(?tmpfile),
  ok              = write_timestamp(?tmpfile, Ts),
  {ok, Ts}        = read_timestamp(?tmpfile),
  ok.

mk_id_test() ->
  Ts    = now_in_ms(),
  Mac   = hw_addr_to_int(lists:seq(1, 6)),
  Seqno = 0,
  Flake = mk_id(Ts, Mac, Seqno),
  <<Ts:64/integer, Mac:48/integer, Sno:16/integer>> = Flake,
  <<FlakeInt:128/integer>>                          = Flake,
  _ = as_list(FlakeInt, 62),
  ok.

integer_to_list_test() ->
  R0 = integer_to_list(5000, 32, []),
  R1 = erlang:integer_to_list(5000, 32),
  R0 = R1,
  ok.

-else.
-endif.

%%%_* Emacs ============================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
