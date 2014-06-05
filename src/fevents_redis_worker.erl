-module(fevents_redis_worker).

-behaviour(gen_server).

-export([start_link/1, q/2, qp/2]).

-export([init/1, handle_call/3, handle_cast/2,
	handle_info/2, terminate/2, code_change/3]).

-include("include/future_events.hrl").

-record(context, {
	redis_context :: 'undefined' | pid(),
	redis_server :: string(),
	redis_port :: pos_integer()
}).

q(Pool, Query) ->
	poolboy:transaction(Pool, 
		fun(Worker) ->
			lager:debug( "wth?" ),
			gen_server:call(Worker, {q, Query}) 
		end).
qp(Pool, Queries) ->
	poolboy:transaction(Pool, 
		fun(Worker) -> 
			gen_server:call(Worker, {qp, Queries}) 
		end).

start_link(Args) ->
	gen_server:start_link(?MODULE, [Args], []).

init([Args]) ->
	process_flag(trap_exit, true), 
	lager:debug( "yea, initialized.. ~p", [Args] ),
	{ok, #context{
		redis_server = proplists:get_value(host, Args),
		redis_port = proplists:get_value(port, Args)
	}}.

get_connection(C) when C#context.redis_context == undefined ->
	case catch eredis:start_link(C#context.redis_server, C#context.redis_port) of
		{ok, Ctx} -> C#context { redis_context = Ctx };
		_ -> C
	end;
get_connection(C) -> C. 

handle_call({q, Query}, _From, State) -> 
	lager:debug( "trying to get a connection..." ),
	S = get_connection(State),
	lager:debug( "got a connection: ~p", [S] ),
	{Reply, NewState} =
		case S#context.redis_context of
			undefined -> {{error, {redis_error, connect_failed}}, S};
			_ ->
				case eredis:q(S#context.redis_context, Query) of
					{error, E} -> 
						{{error, {redis_error, E}}, S#context{ redis_context = undefined }};
					{ok, _} = E -> {E, S}
				end
		end,
	{reply, Reply, NewState};

handle_call({qp, Query}, _From, State) -> 
	S = get_connection(State),
	{Reply, NewState} =
		case S#context.redis_context of
			undefined -> {{error, {redis_error, connect_failed}}, S};
			_ -> 
				case eredis:qp(S#context.redis_context, Query) of
					{error, E} -> 
						{{error, {redis_error, E}}, 
							S#context{ redis_context = undefined }};
					E -> {{ok, E}, S}
				end
		end,
	{reply, Reply, NewState}.

handle_cast(_Msg, State) ->
	{noreply, State}.

handle_info(_R, S) ->
	{noreply, S}.

terminate(_Reason, _State) ->
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.
