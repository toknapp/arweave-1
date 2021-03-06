-module(ar_randomx_state).
-export([start/0, start_block_polling/0, reset/0, hash/2, randomx_state_by_height/1, debug_server/0]).
-export([init/2, init/4, swap_height/1]).
-include("ar.hrl").

-record(state, {
	randomx_states,
	key_cache,
	next_key_gen_ahead
}).

start() ->
	Pid = spawn(fun server/0),
	register(?MODULE, Pid),
	Pid.

start_block_polling() ->
	whereis(?MODULE) ! poll_new_blocks.

reset() ->
	whereis(?MODULE) ! reset.

hash(Height, Data) ->
	case randomx_state_by_height(Height) of
		{state, {fast, FastState}} ->
			ar_mine_randomx:hash_fast(FastState, Data);
		{state, {light, LightState}} ->
			ar_mine_randomx:hash_light(LightState, Data);
		{key, Key} ->
			LightState = ar_mine_randomx:init_light(Key),
			ar_mine_randomx:hash_light(LightState, Data)
	end.

randomx_state_by_height(Height) when is_integer(Height) andalso Height >= 0 ->
	whereis(?MODULE) ! {get_state_by_height, Height, self()},
	receive
		{state_by_height, {ok, State}} ->
			{state, State};
		{state_by_height, {state_not_found, key_not_found}} ->
			SwapHeight = swap_height(Height),
			{ok, Key} = randomx_key(SwapHeight),
			{key, Key};
		{state_by_height, {state_not_found, Key}} ->
			{key, Key}
	end.

debug_server() ->
	whereis(?MODULE) ! {get_state, self()},
	receive
		{state, State} -> State
	end.

init(BHL, Peers) ->
	CurrentHeight = length(BHL) - 1,
	SwapHeights = lists:usort([
		swap_height(CurrentHeight + ?STORE_BLOCKS_BEHIND_CURRENT),
		swap_height(max(0, CurrentHeight - ?STORE_BLOCKS_BEHIND_CURRENT))
	]),
	SwapHeightsFiltered = lists:filter(fun should_init/1, SwapHeights),
	Init = fun(SwapHeight) ->
		{ok, Key} = randomx_key(SwapHeight, BHL, Peers),
		init(whereis(?MODULE), SwapHeight, Key, erlang:system_info(schedulers_online))
	end,
	lists:foreach(Init, SwapHeightsFiltered).

%% PRIVATE

server() ->
	server(init_state()).

init_state() ->
	set_next_key_gen_ahead(#state{
		randomx_states = #{},
		key_cache = #{}
	}).

set_next_key_gen_ahead(State) ->
	State#state{
		next_key_gen_ahead = rand_int(?RANDOMX_MIN_KEY_GEN_AHEAD, ?RANDOMX_MAX_KEY_GEN_AHEAD)
	}.

rand_int(Min, Max) ->
	rand:uniform(Max - Min) + Min - 1.

server(State) ->
	NewState = receive
		poll_new_blocks ->
			poll_new_blocks(State);
		{add_randomx_state, SwapHeight, RandomxState} ->
			State#state{
				randomx_states = maps:put(SwapHeight, RandomxState, State#state.randomx_states)
			};
		{get_state_by_height, Height, From} ->
			case maps:find(swap_height(Height), State#state.randomx_states) of
				error ->
					From ! {state_by_height, {state_not_found, get_key_from_cache(State, Height)}};
				{ok, initializing} ->
					From ! {state_by_height, {state_not_found, get_key_from_cache(State, Height)}};
				{ok, RandomxState} ->
					From ! {state_by_height, {ok, RandomxState}}
			end,
			State;
		{get_state, From} ->
			From ! {state, State},
			State;
		{cache_randomx_key, SwapHeight, Key} ->
			State#state{ key_cache = maps:put(SwapHeight, Key, State#state.key_cache) };
		reset ->
			init_state()
	end,
	server(NewState).

poll_new_blocks(State) ->
	NodePid = whereis(http_entrypoint_node),
	case {ar_node:get_current_block_hash(NodePid), ar_node:get_hash_list(NodePid)} of
		{not_joined, _} ->
			%% Add an extra poll soon
			timer:send_after(1000, poll_new_blocks),
			State;
		{_, []} ->
			%% ar_node:get_hash_list/1 timed out
			timer:send_after(10 * 1000, poll_new_blocks),
			State;
		{_, BHL} ->
			NewState = handle_new_block_hash_list(State, BHL),
			timer:send_after(?RANDOMX_STATE_POLL_INTERVAL * 1000, poll_new_blocks),
			NewState
	end.

handle_new_block_hash_list(State, BHL) ->
	CurrentHeight = length(BHL) - 1,
	State1 = remove_old_randomx_states(State, CurrentHeight),
	case ensure_initialized(State1, swap_height(CurrentHeight)) of
		{started, State2} ->
			maybe_init_next(State2, CurrentHeight);
		did_not_start ->
			maybe_init_next(State1, CurrentHeight)
	end.

remove_old_randomx_states(State, CurrentHeight) ->
	Threshold = swap_height(CurrentHeight - ?RANDOMX_KEEP_KEY),
	IsOutdated = fun(SwapHeight) ->
		SwapHeight < Threshold
	end,
	RandomxStates = State#state.randomx_states,
	RemoveKeys = lists:filter(
		IsOutdated,
		maps:keys(RandomxStates)
	),
	%% RandomX allocates the memory for the dataset internally, bypassing enif_alloc. This presumably causes
	%% GC to be very reluctant to release the memory. Here we explicitly trigger the release. It is scheduled
	%% to happen after some time to account for other processes possibly still using it. In case some process
	%% is still using it, the release call will fail, leaving it for GC to handle.
	lists:foreach(
		fun(Key) ->
			{_, S} = maps:get(Key, RandomxStates),
			timer:apply_after(60000, ar_mine_randomx, release_state, [S])
		end,
		RemoveKeys
	),
	State#state{
		randomx_states = maps_remove_multi(RemoveKeys, RandomxStates)
	}.

maps_remove_multi([], Map) ->
	Map;
maps_remove_multi([Key | Keys], Map) ->
	maps_remove_multi(Keys, maps:remove(Key, Map)).

maybe_init_next(State, CurrentHeight) ->
	NextSwapHeight = swap_height(CurrentHeight) + ?RANDOMX_KEY_SWAP_FREQ,
	case NextSwapHeight - State#state.next_key_gen_ahead of
		_InitHeight when CurrentHeight >= _InitHeight ->
			case ensure_initialized(State, NextSwapHeight) of
				{started, NewState} -> set_next_key_gen_ahead(NewState);
				did_not_start -> State
			end;
		_ ->
			State
	end.

swap_height(Height) ->
	(Height div ?RANDOMX_KEY_SWAP_FREQ) * ?RANDOMX_KEY_SWAP_FREQ.

ensure_initialized(State, SwapHeight) ->
	case should_init(SwapHeight) of
		true ->
			case maps:find(SwapHeight, State#state.randomx_states) of
				{ok, _} ->
					did_not_start;
				error ->
					{started, start_init(State, SwapHeight)}
			end;
		false ->
			did_not_start
	end.

get_key_from_cache(State, Height) ->
	maps:get(swap_height(Height), State#state.key_cache, key_not_found).

%% Initialize RandomX is only needed from the 1.7 fork height and onward,
%% but we initialize pre-fork to test it in shadow mode. If there are any issues,
%% this will increase the likeliness of them being found (and fixed) before the
%% fork happens. For non-RandomX related tests, we care more about performance,
%% so we don't run it in shadow mode for DEBUG.
-ifdef(DEBUG).
should_init(SwapHeight) ->
	SwapHeight >= ar_fork:height_1_7().
-else.
should_init(_SwapHeight) ->
	true.
-endif.

start_init(State, SwapHeight) ->
	Server = self(),
	spawn_link(fun() ->
		init(Server, SwapHeight, 1)
	end),
	State#state{
		randomx_states = maps:put(SwapHeight, initializing, State#state.randomx_states)
	}.

init(Server, SwapHeight, Threads) ->
	case randomx_key(SwapHeight) of
		{ok, Key} ->
			init(Server, SwapHeight, Key, Threads);
		unavailable ->
			ar:warn([ar_randomx_state, failed_to_read_or_download_key_block, {swap_height, SwapHeight}]),
			timer:sleep(5000),
			init(Server, SwapHeight, Threads)
	end.

init(Server, SwapHeight, Key, Threads) ->
	case is_fast_mode_enabled() of
		true ->
			ar:console(
				"Initialising RandomX dataset for fast hashing. Swap height: ~p, Key: ~p. "
				"The process may take several minutes.~n", [SwapHeight, ar_util:encode(Key)]
			),
			Server ! {add_randomx_state, SwapHeight, {fast, ar_mine_randomx:init_fast(Key, Threads)}},
			ar:console("RandomX dataset initialisation for swap height ~p complete.", [SwapHeight]);
		false ->
			ar:console(
				"Initialising RandomX cache for slow low-memory hashing. "
				"Swap height: ~p, Key: ~p~n", [SwapHeight, ar_util:encode(Key)]
			),
			Server ! {add_randomx_state, SwapHeight, {light, ar_mine_randomx:init_light(Key)}},
			ar:console("RandomX cache initialisation for swap height ~p complete.", [SwapHeight])
	end.

%% @doc Return the key used in RandomX by key swap height. The key is the
%% dependent hash from the block at the previous swap height. If RandomX is used
%% already by the first ?RANDOMX_KEY_SWAP_FREQ blocks, then a hardcoded key is
%% used since there is no old enough block to fetch the key from.
randomx_key(SwapHeight) when SwapHeight < ?RANDOMX_KEY_SWAP_FREQ ->
	{ok, <<"Arweave Genesis RandomX Key">>};
randomx_key(SwapHeight) ->
	KeyBlockHeight = SwapHeight - ?RANDOMX_KEY_SWAP_FREQ,
	case get_block(KeyBlockHeight) of
		{ok, KeyB} ->
			Key = KeyB#block.hash,
			whereis(?MODULE) ! {cache_randomx_key, SwapHeight, Key},
			{ok, Key};
		unavailable ->
			unavailable
	end.

get_block(Height) ->
	case ar_node:get_hash_list(whereis(http_entrypoint_node)) of
		[] -> unavailable;
		BHL ->
			BH = lists:nth(Height + 1, lists:reverse(BHL)),
			get_block(BH, BHL)
	end.

get_block(BH, BHL) ->
	case ar_storage:read_block(BH, BHL) of
		unavailable ->
			get_block_remote(BH, BHL);
		B ->
			{ok, B}
	end.

get_block_remote(BH, BHL) ->
	Peers = ar_bridge:get_remote_peers(whereis(http_bridge_node)),
	get_block_remote(BH, BHL, Peers).

get_block_remote(_, _, []) ->
	unavailable;
get_block_remote(BH, BHL, Peers) ->
	case ar_http_iface_client:get_full_block(Peers, BH, BHL) of
		unavailable ->
			unavailable;
		{Peer, B} ->
			case ar_weave:indep_hash(B) of
				BH ->
					ar_storage:write_full_block(B),
					{ok, B};
				InvalidBH ->
					ar:warn([
						ar_randomx_state,
						get_block_remote_got_invalid_block,
						{peer, Peer},
						{requested_block_hash, ar_util:encode(BH)},
						{received_block_hash, ar_util:encode(InvalidBH)}
					]),
					get_block_remote(BH, BHL, Peers)
			end
	end.

randomx_key(SwapHeight, _, _) when SwapHeight < ?RANDOMX_KEY_SWAP_FREQ ->
	randomx_key(SwapHeight);
randomx_key(SwapHeight, BHL, Peers) ->
	KeyBlockHeight = SwapHeight - ?RANDOMX_KEY_SWAP_FREQ,
	case get_block(KeyBlockHeight, BHL, Peers) of
		{ok, KeyB} ->
			{ok, KeyB#block.hash};
		unavailable ->
			unavailable
	end.

get_block(Height, BHL, Peers) ->
	BH = lists:nth(Height + 1, lists:reverse(BHL)),
	case ar_storage:read_block(BH, BHL) of
		unavailable ->
			get_block_remote(BH, BHL, Peers);
		B ->
			{ok, B}
	end.

-ifdef(DEBUG).
is_fast_mode_enabled() -> false.
-else.
is_fast_mode_enabled() -> true.
-endif.
