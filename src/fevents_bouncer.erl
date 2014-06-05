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
		zset_name :: string(),
		scheduledfetch_id :: non_neg_integer()
}).
			


start_link( Args ) ->
	ProcName = proplists:get_value( name, Args ),
	true = is_atom(ProcName),
	gen_server:start_link( {local,ProcName}, ?MODULE, [Args], [] ).




reschedule_fetch( State ) ->
	reschedule_fetch( State, 0, 0 ).


reschedule_fetch( State = #bouncer_state{}, EventCount, _ExpectedEvCount  ) 
		when ?IS_NONNEG_INTEGER(EventCount), ?IS_NONNEG_INTEGER(_ExpectedEvCount)
->
	SchedId = fevents_util:rand_uint16(),
	T = case EventCount of
		0 -> ?T_SLEEP;
		_ -> ?T_NAP
	end,
		
	erlang:send_after( T, self(), {fetch_events,SchedId}  ),
	State#bouncer_state{ scheduledfetch_id=SchedId }.


	
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

	InitState = #bouncer_state{
			name = Name, pool_name = PoolName, 
			event_type = EventType,
			node_counter = NodeCounter, node_indexer = NodeIndexer,
			zset_name = ZSetName
	},

	State = reschedule_fetch( InitState ),
	{ok, State}.



%=====================================================================%

handle_call( {get_prop, zset_name}, _F, State=#bouncer_state{ zset_name=ZSetName } ) ->
	{reply, ZSetName, State};

handle_call( _E, _From, State ) ->
	{noreply, State}.



handle_cast( _Msg, State ) ->
	{noreply, State}.



handle_info( {fetch_events,SchedId}, State = #bouncer_state{ scheduledfetch_id=SchedId } ) ->
	Name = State#bouncer_state.name,
	WPoolName = State#bouncer_state.pool_name,
	EventType = State#bouncer_state.event_type,
	{NCounterMod, NCounterFun} = State#bouncer_state.node_counter,
	{NIndexerMod, NIndexerFun} = State#bouncer_state.node_indexer,
	ZSetName = State#bouncer_state.zset_name,
	T_Now_Str = integer_to_list( fevents_util:unix_timestamp() ),
	MaxChunkSize_Str = integer_to_list( ?MAX_CHUNK_SIZE ),
	NodeIndex = NIndexerMod:NIndexerFun(),
	NodeCount = NCounterMod:NCounterFun(),
	RedisQ = [
			"ZRANGEBYSCORE", ZSetName, "-infinity", T_Now_Str, 
			"WITHSCORES", "LIMIT", "0", MaxChunkSize_Str
	],	

	{OrigCount, EventsParams} = case fevents_redis_worker:q( ?FEVENTS_REDIS_POOL, RedisQ ) of
		{ok, []} ->
			{0, []};
		{ok, L} when ?IS_NONEMPTY_LIST(L) ->
			RevL = lists:reverse( L ),
			NewL = special_zrbscore_filteringzipper( RevL, NodeIndex, NodeCount ),
			{length(L) div 2, NewL}
	end,

	EventCount = length(EventsParams),
	case EventCount > 0 of
		true  -> lager:debug( "~p: Selected ~p events out of ~p fetched", [Name, EventCount, OrigCount] );
		false -> ok
	end,

	Promise = fevents_util:new_promise(),
	lists:foreach(
		fun({T_Scheduled, ObjId}) ->
				fevents_worker:async_consume( WPoolName, EventType, {T_Scheduled, ObjId}, ZSetName, Promise )
		end,
		EventsParams
	),

	PromiseRes = fevents_util:wait_for_promise( Promise, EventCount div 2, EventCount, 5000, 10000 ), 
	case PromiseRes of
		{ok, _} -> ok;
		_       -> lager:error( "~p: Too slow! (tried to consume ~p events)", [Name, EventCount] )
	end,

	NewState = reschedule_fetch( State, EventCount, EventCount ),
	{noreply, NewState};



handle_info( _M, S ) ->
	{noreply, S}.



terminate( _Reason, _State ) ->
	ok.

code_change( _OldVsn, State, _Extra ) ->
	{ok, State}.



%=====================================================================%

special_zrbscore_filteringzipper( [], _, _ ) -> [];

special_zrbscore_filteringzipper( [T_Scheduled_Bin, ObjId | Rest], NodeIndex, NodeCount ) ->
	ObjId_NumHash = crypto:bytes_to_integer( crypto:hash( sha, ObjId ) ),
	ObjId_Index = ObjId_NumHash rem NodeCount,

	case ObjId_Index of
		NodeIndex ->
			% FIXME: should be careful about f.point timestamps
			%
			T_Scheduled = erlang:binary_to_integer( T_Scheduled_Bin ), 
			[{T_Scheduled, ObjId} | special_zrbscore_filteringzipper( Rest, NodeIndex, NodeCount )];
		_ ->
			special_zrbscore_filteringzipper( Rest, NodeIndex, NodeCount )
	end.





