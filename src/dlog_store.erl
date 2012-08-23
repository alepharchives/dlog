%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% @doc
%%% @copyright 2012 Bjorn Jensen-Urstad
%%% @end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-module(dlog_store).
-behaviour(gen_server).

%%%_* Exports ==========================================================
%% api
-export([ start_link/0
        , stop/0

        , get_next_slot/0
        , set_slot_v/2
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
-define(slots_per_file, 5000).

%%%_* Code =============================================================
%%%_ * Types -----------------------------------------------------------
-record(s, { logdir
           , slots
           , prune
           , index
           , logs
           }).

%%%_ * API -------------------------------------------------------------
start_link() ->
  gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop() ->
  call(stop).

get_next_slot() ->
  call(get_next_slot).

set_next_slot(Slot) ->
  call({set_next_slot, Slot}).

set_slot_v(Slot, V) ->
  call({write, Slot, {Slot, V}}).

get_n(Slot) ->
  call({read,  Slot, {n, Slot}}).

get_accepted(Slot) ->
  call({read, Slot, {accepted, Slot}}).

%% REQUIRES diskwrite + flush
set_n(Slot, N) ->
  call({write_sync, Slot, {{n, Slot}, N}}).

%% REQUIRES diskwrite + flush
set_accepted(Slot, N, V) ->
  call({write_sync, Slot, {{accepted, Slot}, {N, V}}}).

%% REQUIRES diskwrite + flush
set_propose(Slot, N, V) ->
  call({write_sync, Slot, {{propose, Slot}, {N, V}}}).

%%%_ * gen_server callbacks --------------------------------------------
init([]) ->
  {ok, Dir}   = application:get_env(dlog, logdir),
  {ok, Slots} = application:get_env(dlog, slots_per_file),
  {ok, Prune} = application:get_env(dlog, prune_after),
  _ = filelib:ensure_dir(filename:join([Dir, "dummy"])),
  Index = open_index(Dir),
  Logs  = open_logs(Dir),
  _ = assert_state(Index, Logs),
  {ok, #s{logdir=Dir, slots=Slots, prune=Prune, index=Index, logs=Logs}}.

terminate(_Rsn, S) ->
  lists:foreach(fun({_, Name}) -> ok = dets:close(Name) end, S#s.logs),
  ok = dets:close(S#s.index),
  ok.

handle_call(stop, _From, S) ->
  {stop, normal, ok, S};
handle_call({read, Slot, Key}, _From, S) ->
  N = slot_to_lognumber(Slot, S#s.slots),
  case lists:keyfind(N, 1, S#s.logs) of
    {N, Name} ->
      case dets:lookup(Name, Key) of
        [{_,V}] -> {reply, {ok, V}, S};
        []      -> {reply, {error, no_such_key}, S}
      end;
    false ->
      {reply, {error, no_such_key}, S}
  end;
handle_call({write_sync, Slot, Obj}, _From, S) ->
  N = slot_to_lognumber(Slot, S#s.slots),
  case lists:keyfind(N, 1, S#s.logs) of
    {N, Name} ->
      ok = dets:insert(Name, Obj),
      ok = dets:sync(Name),
      {reply, ok, S};
    false ->
      Name = open(n_to_file(S#s.logdir, N)),
      ok = dets:insert(Name, Obj),
      ok = dets:sync(Name),
      {reply, ok, S#s{logs=[{N,Name}|S#s.logs]}}
  end;
handle_call({write, Slot, Obj}, _From, S) ->
  N = slot_to_lognumber(Slot, S#s.slots),
  case lists:keyfind(N, 1, S#s.logs) of
    {N, Name} ->
      ok = dets:insert(Name, Obj),
      {reply, ok, S};
    false ->
      Name = open(n_to_file(S#s.logdir, N)),
      ok = dets:insert(Name, Obj),
      {reply, ok, S#s{logs=[{N,Name}|S#s.logs]}}
  end;
handle_call(get_next_slot, _From, S) ->
  {reply, dets:update_counter(S#s.index, next_slot, 1)-1, S}.

handle_cast(_Msg, S) ->
  {stop, bad_cast, S}.

handle_info(Msg, S) ->
  ?warning("~p", [Msg]),
  {noreply, S}.

code_change(_OldVsn, S, _Extra) ->
  {ok, S}.

%%%_ * Internals -------------------------------------------------------
open_index(Dir) ->
  open(index_file(Dir)).

open_logs(Dir) ->
  lists:map(fun(File) ->
                "dlog_log_" ++ NStr = filename:basename(File),
                N = erlang:list_to_integer(NStr),
                {N, open(File)}
            end, log_files(Dir)).

assert_state(Index, Logs) ->
  %%ok=dets:delete(Name, Key),
  dets:insert_new(Index, {next_slot, 1}).

open(File) ->
  Name = erlang:list_to_atom(File),
  {ok, Name} = dets:open_file(Name, [{file, File}, {auto_save, infinity}]),
  Name.

close(Name) ->
  ok = dets:close(Name).

slot_to_lognumber(Slot, SlotsPerFile) ->
  (Slot - (Slot rem SlotsPerFile)) div SlotsPerFile.

n_to_file(LogDir, N) ->
  Fn = lists:flatten(io_lib:format("dlog_log_~20..0B", [N])),
  filename:join([LogDir, Fn]).

call(Args) -> gen_server:call(?MODULE, Args).

log_files(Dir) ->
  filelib:wildcard(filename:join([Dir, "dlog_log_*"])).

index_file(Dir) ->
  filename:join([Dir, "dlog_index"]).

%%%_* Tests ============================================================
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

next_slot_test() ->
  _ = application:load(dlog),
  _ = clean(),
  {ok, _} = dlog_store:start_link(),
  1 = get_next_slot(),
  2 = get_next_slot(),
  3 = get_next_slot(),
  dlog_store:stop(),
  ok.

slot_to_file_test() ->
  ok.

filename_test() ->
  N1 = n_to_file("foo", 1),
  N2 = n_to_file("foo", 100000),
  true = length(N1) =:= length(N2),
  ok.

basic_test() ->
  _ = application:load(dlog),
  _ = clean(),
  {ok, Pid} = dlog_store:start_link(),
  ok        = set_n(123, 456),
  {ok, 456} = get_n(123),
  dlog_store:stop(),
  ok.

clean() ->
  {ok, Dir} = application:get_env(dlog, logdir),
  lists:foreach(fun(File) ->
                    _ = file:delete(File)
                end, [index_file(Dir) | log_files(Dir)]).

-endif.

%%%_* Emacs ============================================================
%%% Local Variables:
%%% allout-layout: t
%%% erlang-indent-level: 2
%%% End:

