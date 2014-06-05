

-type fevent_handler() :: {atom(), atom()}.
-type node_indexer() :: {atom(), atom()}.
-type node_counter() :: {atom(), atom()}.


-define(IS_NONNEG_INTEGER(N), (is_integer(N) andalso N >= 0)).
-define(IS_POS_INTEGER(N), (is_integer(N) andalso N > 0)).

-define(IS_NONEMPTY_LIST(L), (is_list(L) andalso length(L) > 0)).

-define(IS_DEFINED(V), (V =/= undefined)).

-define(FEVENTS_REDIS_POOL, fevents_redis_pool).
