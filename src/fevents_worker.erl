-module(fevents_worker).


-behaviour(gen_server).
-export([start_link/1]).

-export([
	init/1, handle_call/3, handle_cast/2,
	handle_info/2, terminate/2, code_change/3
]).


-include("include/future_events.hrl").


-record(worker_params, {
		event_handler :: fevent_handler()
}).
		


start_link(Args ) ->
    gen_server:start_link( ?MODULE, [Args], [] ).


init( [Args] ) ->
	process_flag( trap_exit, true ),
	{Module, Function} = proplists:get_value( event_handler, Args ),
	{ok, #worker_params{ event_handler = {Module,Function} }}.



handle_call( _, _, State ) ->
	{noreply, State}.



handle_cast( {new_event, EventType, {ScheduledTimestamp, ObjectId}, Promise}, State = #worker_params{} ) ->
	{Module, Function} = State#worker_params.event_handler,
	Response = apply( Module, Function, [EventType, ScheduledTimestamp, ObjectId] ),
	fevents_util:keep_promise( Promise, Response ),
	{noreply, State};


handle_cast( _, State ) ->
	{noreply, State}.



handle_info( _, S ) ->
	{noreply, S}.



terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
