%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc
%%% @copyright 2012 Bjorn Jensen-Urstad
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%_* Module declaration ===============================================
-module(dlog_sup).
-behaviour(supervisor).

%%%_* Exports ==========================================================
-export([start_link/1, init/1]).

%%%_* Code =============================================================
start_link(Args) ->
  supervisor:start_link({local, ?MODULE}, ?MODULE, Args).

init(_Args) ->
  %%RestartStrategy = {one_for_one, 4, 10},
  RestartStrategy = {one_for_all, 0, 1},

  Kids = [ {dlog_store,
            {dlog_store, start_link, []},
            permanent, 5000, worker, [dlog_store]}
         , {dlog_transport,
            {dlog_transport, start_link, []},
            permanent, 5000, worker, [dlog_transport]}
         , {dlog_server,
            {dlog_server, start_link, []},
            permanent, 5000, worker, [dlog_server]}
         ],
  {ok, {RestartStrategy, Kids}}.

%%%_* Tests ============================================================

%%%_* Emacs ============================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:
