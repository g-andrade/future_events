-module(fevents_bouncer).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3, start_link/1]).

-include("include/future_events.hrl").


-define(MAX_CHUNK_SIZE, 100).
-define(T_SLEEP, 5000).
-define(T_NAP, 200).



-record(bouncer_state, {	
		name :: atom(),
		pool_name :: atom(),
		event_type = undefined,
		node_counter :: node_counter(),
		node_indexer :: node_indexer(),
		zset_name :: string()
}).
			


start_link( Args ) ->
	ProcName = proplists:get_value( name, Args ),
	true = is_atom(ProcName),
	gen_server:start_link( {local,ProcName}, ?MODULE, [Args], [] ).


	
init( [Args] ) ->
	Name = proplists:get_value( name, Args ),
	PoolName = proplists:get_value( pool_name, Args ),
	EventType = proplists:get_value( event_type, Args ),
	true = (EventType =/= undefined),
	{Mod1,Fun1} = proplists:get_value( nodecount_function, Args ),
	NodeCounter = {Mod1,Fun1},
	{Mod2,Fun2} = proplists:get_value( nodeindex_function, Args ),
	NodeIndexer = {Mod2,Fun2},
	ZSetName = proplists:get_value( zset_name, Args ),
	true = is_list(ZSetName) andalso (length(ZSetName) > 0),

	erlang:send_after( ?T_NAP, self(), fetch_events  ),

	{ok, #bouncer_state{
			name = Name, pool_name = PoolName, event_type = EventType,
			node_counter = NodeCounter, node_indexer = NodeIndexer,
			zset_name = ZSetName
	}}.



handle_call( _E, _From, State ) ->
	{noreply, State}.


handle_cast( _Msg, State ) ->
	{noreply, State}.



handle_info( fetch_events, State = #bouncer_state{} ) ->
	Name = State#bouncer_state.name,
	PoolName = State#bouncer_state.pool_name,
	EventType = State#bouncer_state.event_type,
	NodeCounter = State#bouncer_state.node_counter,
	NodeIndexer = State#bouncer_state.node_indexer,
	ZSetName = State#bouncer_state.zset_name,
	lager:debug( "Fetching new events for ~p..", [Name] ),

	T_Now_Str = integer_to_list( swiss:unix_timestamp() ),
	MaxChunkSize_Str = integer_to_list( ?MAX_CHUNK_SIZE ),
	RedisQ = [
			"ZRANGEBYSCORE", ZSetName, "-infinity", T_Now_Str, 
			"WITHSCORES", "LIMIT", "-1", MaxChunkSize_Str
	],

	Events = case fevents_redis_worker:q( PoolName, RedisQ ) of
		{ok, R} ->
			lager:debug( "Got something! ~p", [R] )
	end,

	erlang:send_after( ?T_SLEEP, self(), fetch_events ),
	{noreply, State};


handle_info( _M, S ) ->
	{noreply, S}.



terminate( _Reason, _State ) ->
	ok.

code_change( _OldVsn, State, _Extra ) ->
	{ok, State}.

