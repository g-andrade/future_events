-module(fevents_bouncer).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3, start_link/1]).


-include("include/future_events.hrl").


-record(bouncer_state, {	
		name :: atom(),
		pool_name :: atom(),
		event_type = undefined,
		node_counter :: node_counter(),
		node_indexer :: node_indexer()
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

	{ok, #bouncer_state{
			name = Name, pool_name = PoolName, event_type = EventType,
			node_counter = NodeCounter, node_indexer = NodeIndexer 
	}}.



handle_call( _E, _From, State ) ->
	{noreply, State}.


handle_cast( _Msg, State ) ->
	{noreply, State}.


handle_info( _M, S ) ->
	{noreply, S}.


terminate( _Reason, _State ) ->
	ok.

code_change( _OldVsn, State, _Extra ) ->
	{ok, State}.

