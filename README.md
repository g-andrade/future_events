future_events
=============

Using Redis' <a href="http://redis.io/commands/ZRANGEBYSCORE">ZSET</a> to implement long-lived timeout events. Functional but still requiring some work (and thinking).

---------------------------------------------------------

	future_events:schedule/3 [BouncerName :: atom(), T_Deadline :: non_neg_integer(), ObjId :: binary() | string()]
	future_events:cancel/2 [BouncerName : atom(), ObjId :: binary() | string()]

---------------------------------------------------------

reltool / rebar:

	{future_events, [
				{poolboy, [
						{fevents_redis_pool, 
							[
								{size, 20},
								{max_overflow, 10},
								{worker_module, fevents_redis_worker}
							], [
								{host, "127.0.0.1"}, {port, 6379}	
							]
						},
	%					{fevents_someentity_pool, 
	%						[
	%							{size, 20},
	% 							{max_overflow, 10},
	% 							{worker_module, fevents_worker}
	% 						], [
	% 							{event_handler, {your_own_module, your_own_function}} % fun/3 [EventType, T_Scheduled, ObjId]
	% 						]
	% 					}
				]},

				{bouncers, [
	% 					{someentity_timeouts, [
	% 							{pool_name,  fevents_someentity_pool},
	% 							{event_type, someentity_specific_kind_of_timeout},
	% 							{nodecount_function, {your_own_module, your_own_function}}, % fun/0 -> number of nodes in cluster
	% 							{nodeindex_function, {your_own_module, your_own_function}}, % fun/0 -> unique index for this node in cluster (0 based)
	% 							{zset_name, "someentity_timeouts"}
	% 					]}
				]}
	]}

