-module (flake_util).
-export ([as_list/2]).
-export ([get_if_hw_int/1,hw_addr_to_int/1]).

% get the mac/hardware address of the given interface as a 48-bit integer
get_if_hw_int(undefined) ->
  {error,if_not_found};
get_if_hw_int(IfName) ->
  {ok,IfAddrs} = inet:getifaddrs(),
  IfProps = proplists:get_value(IfName,IfAddrs),
  case IfProps of
    undefined ->
      {error,if_not_found};
    _ ->
      HwAddr = proplists:get_value(hwaddr,IfProps),
      {ok,hw_addr_to_int(HwAddr)}
  end.

% convert an array of 6 bytes into a 48-bit integer
hw_addr_to_int(HwAddr) ->
  <<WorkerId:48/unsigned-integer>> = erlang:list_to_binary(HwAddr),
  WorkerId.

%%
% n.b. - unique_id_62/0 and friends pulled from riak
%%

%% @spec integer_to_list(Integer :: integer(), Base :: integer()) ->
%%          string()
%% @doc Convert an integer to its string representation in the given
%%      base.  Bases 2-62 are supported.
as_list(I, 10) ->
    erlang:integer_to_list(I);
as_list(I, Base)
  when is_integer(I),
       is_integer(Base),
       Base >= 2,
       Base =< 1+$Z-$A+10+1+$z-$a ->
  if
    I < 0 ->
      [$-|as_list(-I, Base, [])];
    true ->
      as_list(I, Base, [])
    end;
as_list(I, Base) ->
  erlang:error(badarg, [I, Base]).

%% @spec integer_to_list(integer(), integer(), stringing()) -> string()
as_list(I0, Base, R0) ->
  D = I0 rem Base,
  I1 = I0 div Base,
  R1 =
    if
      D >= 36 ->
        [D-36+$a|R0];
      D >= 10 ->
        [D-10+$A|R0];
      true ->
        [D+$0|R0]
    end,
  if
    I1 =:= 0 ->
      R1;
    true ->
      as_list(I1, Base, R1)
  end.