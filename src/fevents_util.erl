-module(fevents_util).

-export([
	unix_timestamp/0, unix_timestamp_ms/0,
	rand_uint16/0,
	new_promise/0, keep_promise/2, wait_for_promise/3, wait_for_promise/5
]).



unix_timestamp() ->
	{Msec, Sec, _} = os:timestamp(),
	Msec * 1000000 + Sec.

unix_timestamp_ms() ->
	{A, B, C} = os:timestamp(),
	(((A * 1000000) + B) * 1000) + C div 1000.



rand_uint16() ->
	rand_uint( 2 ).

rand_uint( ByteCount ) ->
	binary:decode_unsigned( rand_bin(ByteCount), little ).

rand_bin( ByteCount ) ->
	crypto:rand_bytes( ByteCount ).



new_promise() ->
	{rand_uint16(), self()}.



keep_promise( PromiseRef, Response ) ->
	{PromiseId, WaiterPid} = PromiseRef,
	true = (WaiterPid =/= self()),
	WaiterPid ! {promise_kept, PromiseId, Response}.



wait_for_promise( PromiseRef, ResponseCount, Timeout ) ->
	wait_for_promise( PromiseRef, ResponseCount, ResponseCount, Timeout, Timeout ).


wait_for_promise( _, 0, 0, _, _ ) ->
	{ok, []};


wait_for_promise( PromiseRef, MinR, MaxR, SoftTimeout, HardTimeout )
		when is_integer(MinR) andalso is_integer(MaxR) 
			andalso (MaxR >= MinR) andalso SoftTimeout >= 0 
			andalso HardTimeout > 0 andalso (HardTimeout >= SoftTimeout)
->
	OwnPid = self(),
	{PromiseId, OwnPid} = PromiseRef,
	T_A = unix_timestamp_ms(),
	SoftDeadline = T_A + SoftTimeout,
	HardDeadline = T_A + HardTimeout,

	SoftTimerRef = erlang:send_after( SoftTimeout, self(), {good_enough, PromiseId} ),
	HardTimerRef = erlang:send_after( HardTimeout, self(), {promises_are_over, PromiseId} ),

	WaitFun = fun(F, PreviousResponses, CountSoFar) ->
			T_B = unix_timestamp_ms(),

			case {CountSoFar, T_B} of
				_ when (CountSoFar >= MinR) andalso (T_B >= SoftDeadline) ->
					erlang:cancel_timer( HardTimerRef ),
					Responses = lists:sublist( PreviousResponses, MaxR ),
					{ok, Responses};

				_ when (CountSoFar >= MaxR) ->
					erlang:cancel_timer( SoftTimerRef ),
					erlang:cancel_timer( HardTimerRef ),
					Responses = lists:sublist( PreviousResponses, MaxR ),
					{ok, Responses};

				_ when (CountSoFar < MinR)  andalso (T_B >= HardDeadline) ->
					{error, liars};

				_ ->
					receive 
						{promise_kept, PromiseId, Response} ->
							F( F, [Response | PreviousResponses], CountSoFar+1 );
						{promises_are_over, PromiseId} ->
							F( F, PreviousResponses, CountSoFar );
						{good_enough, PromiseId} ->
							F( F, PreviousResponses, CountSoFar )
					end
			end
	end,
	WaitFun( WaitFun, [], 0 ).
