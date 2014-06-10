-module(future_events).

-behaviour(application).
-export([start/2, stop/1]).

-behaviour(supervisor).
-export([init/1]).


-export([
	schedule/3, schedule_by_zset/3,
	cancel/2, cancel_by_zset/2
]).


-include("include/future_events.hrl").



% Ergh. Think of a better way later.
%
schedule( BouncerName, T_Deadline, ObjId ) when is_atom(BouncerName) ->
	ZSetName = gen_server:call( whereis(BouncerName), {get_prop, zset_name} ),
	schedule_by_zset( ZSetName, T_Deadline, ObjId ).

schedule_by_zset( ZSetName, T_Deadline, ObjId ) when is_list(ZSetName) ->
	fevents_worker:async_schedule( ZSetName, T_Deadline, ObjId ). 



% Ergh. Think of a better way later.
%
cancel( BouncerName, ObjId ) when is_atom(BouncerName) ->
	ZSetName = gen_server:call( whereis(BouncerName), {get_prop, zset_name} ),
	cancel_by_zset( ZSetName, ObjId ).

cancel_by_zset( ZSetName, ObjId ) when is_list(ZSetName) ->
	fevents_worker:async_cancel( ZSetName, ObjId ).



%=====================================================================%

start( _, _ ) ->
	{ok, Pools} = application:get_env( poolboy ),
	{ok, Bouncers} = application:get_env( bouncers ),
	supervisor:start_link( {local, ?MODULE}, ?MODULE, [Pools, Bouncers] ).


stop( _ ) ->
	ok.


init( [Pools, Bouncers] ) ->
	RestartStrategy = one_for_one,
	MaxRestarts = 10,
	MaxSecondsBetweenRestarts = 10,
	SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},
	PB_RestartType = permanent,
	PB_Shutdown_T = 5000,
	PoolSpecs = lists:map( 
			fun({PoolName, PoolConfig, WorkerArgs}) ->
					Args = [{name, {local, PoolName}}] ++ PoolConfig,
					{
						PoolName, {poolboy, start_link, [Args, WorkerArgs]},
						PB_RestartType, PB_Shutdown_T, worker, []
					}
			end,
			Pools
	),

	BouncerRestartType = permanent,
	BouncerShutdown_T = 5000,
	BouncerSpecs = lists:map(
			fun({BouncerName, BouncerArgs}) ->
					FinalArgs = [{name, BouncerName}] ++ BouncerArgs,
					{
						BouncerName, {fevents_bouncer, start_link, [FinalArgs]},
						BouncerRestartType, BouncerShutdown_T, worker, [fevents_bouncer]
					}
			end,
			Bouncers
	),
				
	ChildSpecs = PoolSpecs ++ BouncerSpecs,
	{ok, {SupFlags, ChildSpecs}}.




