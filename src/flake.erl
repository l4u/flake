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
-module (flake).

%%%_* Exports ==========================================================
-export([ id/0
        , id/1
        ]).

%%%_* Code =============================================================
%%%_ * API -------------------------------------------------------------
%% @doc id() -> binary()
id() -> flake_server:id().

%% @doc id(Base::integer()) -> list()
id(Base) -> flake_server:id(Base).

%%%_* Tests ============================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

generate_base_48_test() ->
  ok = application:start(flake, permanent),
  {ok, IdStr0} = flake:id(48),
  {ok, IdStr1} = flake:id(48),
  application:stop(flake),
  ok.

generate_10k_ids_test() ->
  application:start(flake, permanent),
  generate(10000),
  application:stop(flake),
  ok.

generate(0) -> ok;
generate(N) ->
  {ok, <<Int:128/integer>>} = flake:id(),
  erlang:is_integer(Int),
  generate(N-1).

-else.
-endif.

%%%_* Emacs ============================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
