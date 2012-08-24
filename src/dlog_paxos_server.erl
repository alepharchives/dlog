%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc Entrance for all paxos related communication
%%% @copyright 2012 Bjorn Jensen-Urstad
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-module(dlog_paxos_server).
-behaviour(gen_server).

%%%_* Exports ==========================================================
%% api
-export([ start_link/0
        ]).

-export([ init/1
        , terminate/2
        , handle_call/3
        , handle_cast/2
        , handle_info/2
        , code_change/3
        ]).

%%%_* Includes =========================================================
-include_lib("dlog/include/dlog.hrl").

%%%_* Macros ===========================================================
%%%_* Code =============================================================
%%%_ * Types -----------------------------------------------------------
-record(s, { id
           , nodes
           , quorum
           , fsms=dict:new()
           }).

-record(fsm, {pid}).

%%%_ * API -------------------------------------------------------------
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

submit(V, Timeout) ->
  gen_server:call(?MODULE, {submit, V, Timeout}, infinity).

%%%_ * gen_server callbacks --------------------------------------------
init([]) ->
  {ok, ID}    = application:get_env(paxos, id),
  {ok, Nodes} = application:get_env(paxos, nodes),
  Quorum      = paxos_util:quorum(erlang:length(Nodes)),
  {ok, #s{nodes=Nodes, id=ID}}.

terminate(_Rsn, S) ->
  ok.

handle_call({submit, V, _Timeout}, From, #s{fsms=Fsms0} = S) ->
  %% no timeouts for now
  Slot = dlog_store:get_next_slot(),
  {ok, Pid} = dlog_paxos_fsm:start_link(Slot, V),
  Fsms1 = dict:insert({pid, Pid}, {Slot, From}, Fsms0),
  Fsms  = dict:insert({slot, Slot}, Pid, Fsms1),
  {reply, ok, S#s{fsms=Fsms}}.

handle_cast(_Msg, S) ->
  {stop, bad_cast, S}.

handle_info({paxos, _} = Msg, S) ->
  

handle_info({Node, {prepare, Slot, N}}, #s{} = S) ->
  %% NOTE: check for already accepted
  case dlog_store:get_n(Slot) of
    {ok, Sn}
      when N > Sn ->
      {PrevN, PrevV} =
        case dlog_store:get_accepted(Slot) of
          {ok, {Hn, Hv}} -> {Hn, Hv};
          {error, no_such_key} -> {null, null}
        end,
      ok = dlog_store:set_n(Slot, N),
      paxos_util:send(Node, {promise, PrevN, PrevV}),
      {noreply, S};
    {ok, Sn} ->
      paxos_util:send(Node, {reject, Sn}),
      {noreply, S};
    {error, no_such_key} ->
      ok = dlog_store:set_n(Slot, N),
      paxos_util:send(Node, {promise, null, null}),
      {noreply, S}
  end;
handle_info({Node, {propose, Slot, N, V}}, #s{nodes=Nodes} = S) ->
  %% NOTE: check for already accepted
  case dlog_store:get_n(Slot) of
    HN when HN =< N ->
      dlog_store:set_accepted(Slot, N, V),
      %% dlog_store:set_slot_v(Slot, V),
      %% send accept msg to just coordinator? have coordinator order accept?
      paxos_util:broadcast(Nodes, {accepted, Slot, N, V}),
      {noreply, S};
    _ ->
      {noreply, S}
  end;
handle_info({Node, {accepted, Slot, N, V}


handle_info({Node, {accept, Slot, N, V}}, #s{} = S) ->
  dlog_store:set_slot_v(Slot, V),
  {noreply, S};
handle_info(Msg, S) ->
  ?warning("~p", [Msg]),
  {noreply, S}.

code_change(_OldVsn, S, _Extra) ->
  {ok, S}.

%%%_ * Internals -------------------------------------------------------

get_next_n(N, All)-> ((N div All)+1) * All.


%%%_* Emacs ============================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End: