-module(fevents_worker).

-behaviour(gen_server).
-export([start_link/1]).

-export([
	init/1, handle_call/3, handle_cast/2,
	handle_info/2, terminate/2, code_change/3,

	async_consume/5, async_schedule/3, async_cancel/2
]).


-include("include/future_events.hrl").

-record(worker_params, {
		event_handler :: fevent_handler()
}).
		


-define(DEFAULT_RESCHEDULE_DIFF, +300).


%=====================================================================%

async_consume( PoolName, EventType, {T_Scheduled, ObjId}, ZSetName, Promise ) 
		when is_atom(EventType), ?IS_POS_INTEGER(T_Scheduled), ?IS_DEFINED(ObjId), ?IS_DEFINED(Promise)
->
	Msg = {new_event, EventType, {T_Scheduled, ObjId}, ZSetName, Promise},
	TrxFun = fun(Worker) -> gen_server:cast( Worker, Msg ) end,
	poolboy:transaction( PoolName, TrxFun ).



async_schedule( ZSetName, T_Deadline, ObjId ) ->
	spawn( fun() -> schedule(ZSetName, T_Deadline, ObjId) end ),
	ok.

schedule( ZSetName, T_Deadline, ObjId ) ->
	Q = ["ZADD", ZSetName, integer_to_list(T_Deadline), ObjId], 
	Res = fevents_redis_worker:q( ?FEVENTS_REDIS_POOL, Q ),
	case Res of
		{ok, _} -> 
			lager:debug( "~p/~p scheduled for ~p", [ZSetName, ObjId, T_Deadline] ),
			ok;
		{error, Why} ->
			lager:warning( "~p/~p failed to schedule! ~p", [ZSetName, ObjId, Why] ),
			{error, Why}
	end.



async_cancel( ZSetName, ObjId ) ->
	spawn( fun() -> cancel(ZSetName, ObjId) end ),
	ok.

cancel( ZSetName, ObjId ) when ?IS_NONEMPTY_LIST(ZSetName), ?IS_DEFINED(ObjId) ->
	Q = ["ZREM", ZSetName, ObjId],
	Res = fevents_redis_worker:q( ?FEVENTS_REDIS_POOL,Q ),
	case Res of
		{ok, _} -> 
			lager:debug( "~p/~p canceled.", [ZSetName, ObjId] ),
			ok;
		{error, Why} ->
			lager:warning( "~p/~p failed to cancel! ~p", [ZSetName, ObjId, Why] ),
			{error, Why}
	end.



%=====================================================================%

start_link(Args ) ->
    gen_server:start_link( ?MODULE, [Args], [] ).


init( [Args] ) ->
	process_flag( trap_exit, true ),
	{Module, Function} = proplists:get_value( event_handler, Args ),
	{ok, #worker_params{ event_handler = {Module,Function} }}.



handle_call( _, _, State ) ->
	{noreply, State}.



handle_cast( {new_event, EventType, {T_Scheduled, ObjId}, ZSetName, Promise}, State = #worker_params{} ) ->
	{Module, Function} = State#worker_params.event_handler,
	Response = apply( Module, Function, [EventType, T_Scheduled, ObjId] ),

	PromiseResponse = case Response of
		ok -> 
			ok = cancel( ZSetName, ObjId ),
			lager:debug( "Consumed ~p/~p", [ZSetName, ObjId] ),
			ok;
		{error, Why} ->
			lager:warning( "Failed to consume ~p/~p: ~p", [ZSetName, ObjId, Why] ),
			New_T_Deadline = fevents_util:unix_timestamp() + ?DEFAULT_RESCHEDULE_DIFF,
			ok = schedule( ZSetName, New_T_Deadline, ObjId ),
			{error, Why}
	end,

	fevents_util:keep_promise( Promise, PromiseResponse ),
	{noreply, State};


handle_cast( _, State ) ->
	{noreply, State}.



handle_info( _, S ) ->
	{noreply, S}.



terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
