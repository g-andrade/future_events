-module(future_events).

-behaviour(application).
-export([ start/2, stop/1 ]).

-behaviour(supervisor).
-export([ init/1 ]).


-include("include/future_events.hrl").


start( _, _ ) ->
	{ok, Pools} = application:get_env( poolboy ),
	supervisor:start_link( {local, ?MODULE}, ?MODULE, [Pools] ).


stop( _ ) ->
	ok.


init( [Pools] ) ->
	RestartStrategy = one_for_one,
	MaxRestarts = 10,
	MaxSecondsBetweenRestarts = 10,
	SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},
	PB_RestartType = permanent,
	PB_ShutdownN = 5000,
	PB_Type = worker,

	PoolSpecs = lists:map( 
			fun({PoolName, PoolConfig, WorkerArgs}) ->
					Args = [{name, {local, PoolName}}] ++ PoolConfig,
					{
						PoolName, {poolboy, start_link, [Args, WorkerArgs]},
						PB_RestartType, PB_ShutdownN, PB_Type, []
					}
			end,
			Pools
	),

	{ok, {SupFlags, PoolSpecs}}.
