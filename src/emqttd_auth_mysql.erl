%%--------------------------------------------------------------------
%% Copyright (c) 2012-2016 Feng Lee <feng@emqtt.io>.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

%% @doc Authentication with MySQL Database.
-module(emqttd_auth_mysql).

-behaviour(emqttd_auth_mod).

-include("emqttd_auth_mysql.hrl").

-include_lib("emqttd/include/emqttd.hrl").

-import(emqttd_auth_mysql_client, [is_superuser/2, query/3]).

-export([pool_name/1]).

-export([init/1, check/3, description/0]).

-record(state, {super_query, auth_query, hash_type}).

-define(EMPTY(Username), (Username =:= undefined orelse Username =:= <<>>)).

pool_name(Pool) ->
    list_to_atom(lists:concat([?APP, '_', Pool])).

init({SuperQuery, AuthQuery, HashType}) ->
    {ok, #state{super_query = SuperQuery, auth_query = AuthQuery, hash_type = HashType}}.

check(#mqtt_client{username = Username}, _Password, _State) when ?EMPTY(Username) ->
    {error, username_undefined};

check(Client, Password, #state{super_query = SuperQuery}) when ?EMPTY(Password) ->
    case is_superuser(SuperQuery, Client) of
        true  -> ok;
        false -> {error, password_undefined}
    end;

check(Client, Password, #state{super_query = SuperQuery,
                               auth_query  = {AuthSql, AuthParams},
                               hash_type   = HashType}) ->
    case is_superuser(SuperQuery, Client) of
        false -> case query(AuthSql, AuthParams, Client) of
                    {ok, [<<"password">>], [[PassHash]]} ->
                        check_pass(PassHash, Password, HashType);
                    {ok, [<<"password">>, <<"salt">>], [[PassHash, Salt]]} ->
                        check_pass(PassHash, Salt, Password, HashType);
                    {ok, _Columns, []} ->
                        {error, notfound};
                    {error, Error} ->
                        {error, Error}
                 end;
        true  -> ok
    end.

check_pass(PassHash, Password, HashType) ->
    check_pass(PassHash, hash(HashType, Password)).
check_pass(PassHash, Salt, Password, {salt, HashType}) ->
    check_pass(PassHash, hash(HashType, <<Salt/binary, Password/binary>>));
check_pass(PassHash, Salt, Password, {HashType, salt}) ->
    check_pass(PassHash, hash(HashType, <<Password/binary, Salt/binary>>)).

check_pass(PassHash, PassHash) -> ok;
check_pass(_, _)               -> {error, password_error}.

description() -> "Authentication with MySQL".

hash(Type, Password) -> emqttd_auth_mod:passwd_hash(Type, Password).

